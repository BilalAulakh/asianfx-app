-- ==============================================================================
-- MIGRATION: 20261012000000_single_deposit_address.sql
--
-- ONE company deposit address, set by the admin. The A,A,A,B rotation (every
-- 4th deposit went to the automatic Address B) is removed.
--
--   * Every automatic address (Address B) is deactivated. Rows are kept for
--     history; deposits already WAITING on B are still verified and credited by
--     the auto-verify-deposits job as before.
--   * fx_assign_deposit_address() always returns the admin's address (the
--     single active manual address; falls back to broker_config's address).
--     Automatic addresses are never assigned, even if re-added later.
--   * rpc_admin_set_deposit_address() makes the saved address the ONLY active
--     one (any other address, automatic or manual, is deactivated).
--   * rpc_create_deposit_request() resumes a user's open request only if it is
--     on the current address; an old open request on Address B is left alone
--     and a new one is created on the admin's address.
--
-- Requires 20261006000100 / 20261006000200 / 20261006000400. Idempotent.
-- ==============================================================================

-- 1. Address B (and any other automatic address) leaves service.
UPDATE public.company_deposit_addresses
   SET is_active = FALSE, updated_at = NOW()
 WHERE auto_verify AND is_active;

-- 2. Assignment: the admin's single address, no rotation.
CREATE OR REPLACE FUNCTION public.fx_assign_deposit_address()
RETURNS public.company_deposit_addresses
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_row public.company_deposit_addresses;
    v_cfg TEXT;
BEGIN
    SELECT * INTO v_row
    FROM public.company_deposit_addresses
    WHERE is_active AND NOT auto_verify
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1;
    IF FOUND THEN
        RETURN v_row;
    END IF;

    -- No row yet: use the address configured on the admin desk, if valid.
    SELECT btrim(deposit_address_trc20) INTO v_cfg FROM public.broker_config WHERE id = 1;
    IF v_cfg ~ '^T[1-9A-HJ-NP-Za-km-z]{33}$' THEN
        INSERT INTO public.company_deposit_addresses
            (address, label, weight, sort_order, is_active, auto_verify, max_auto_approve_usd)
        VALUES (v_cfg, 'Company deposit address', 1, 0, TRUE, FALSE, 1000)
        ON CONFLICT (address) DO UPDATE
            SET is_active = TRUE, auto_verify = FALSE, weight = 1, updated_at = NOW()
        RETURNING * INTO v_row;
        RETURN v_row;
    END IF;

    RAISE EXCEPTION 'DEPOSITS_DISABLED: no company deposit address is set. Please contact support.'
        USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.fx_assign_deposit_address() FROM PUBLIC, anon, authenticated;

-- 3. Admin: the saved address becomes the only active address.
CREATE OR REPLACE FUNCTION public.rpc_admin_set_deposit_address(p_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_new   TEXT;
    v_old   TEXT;
BEGIN
    v_admin := public.fx_require_admin();

    v_new := btrim(COALESCE(p_address, ''));
    IF v_new !~ '^T[1-9A-HJ-NP-Za-km-z]{33}$' THEN
        RAISE EXCEPTION 'BAD_ADDRESS: enter a valid TRC-20 address (starts with T, 34 characters)'
            USING ERRCODE = '22023';
    END IF;

    -- Serialise with concurrent deposit requests.
    PERFORM 1 FROM public.deposit_rotation_state WHERE id = 1 FOR UPDATE;

    SELECT address INTO v_old
    FROM public.company_deposit_addresses
    WHERE is_active AND NOT auto_verify
    ORDER BY updated_at DESC, created_at DESC
    LIMIT 1;

    -- Every other address leaves service (rows kept for history).
    UPDATE public.company_deposit_addresses
       SET is_active = FALSE, updated_at = NOW()
     WHERE address <> v_new AND is_active;

    INSERT INTO public.company_deposit_addresses
        (address, label, weight, sort_order, is_active, auto_verify, max_auto_approve_usd)
    VALUES (v_new, 'Company deposit address', 1, 0, TRUE, FALSE, 1000)
    ON CONFLICT (address) DO UPDATE
        SET label = 'Company deposit address', weight = 1, sort_order = 0,
            is_active = TRUE, auto_verify = FALSE, updated_at = NOW();

    UPDATE public.broker_config
       SET deposit_address_trc20 = v_new, updated_at = NOW()
     WHERE id = 1;

    IF v_old IS DISTINCT FROM v_new THEN
        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_deposit_address', 'company_deposit_addresses',
                jsonb_build_object('deposit_address', v_old),
                jsonb_build_object('deposit_address', v_new));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'deposit_address', v_new, 'previous', v_old);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) TO authenticated;

-- 4. Make the current admin address the single active one right now
--    (covers databases where Address A was set before this migration).
DO $$
DECLARE v_cur public.company_deposit_addresses;
BEGIN
    SELECT * INTO v_cur FROM public.company_deposit_addresses
    WHERE is_active AND NOT auto_verify
    ORDER BY updated_at DESC, created_at DESC LIMIT 1;
    IF FOUND THEN
        UPDATE public.company_deposit_addresses
           SET is_active = FALSE, updated_at = NOW()
         WHERE is_active AND address <> v_cur.address;
        UPDATE public.company_deposit_addresses
           SET weight = 1, label = 'Company deposit address', updated_at = NOW()
         WHERE address = v_cur.address;
    END IF;
END $$;

-- 5. Deposit request: resume an open request only on the current address.
CREATE OR REPLACE FUNCTION public.rpc_create_deposit_request(
    p_amount     NUMERIC,
    p_request_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid   TEXT;
    v_cfg   public.broker_config;
    v_addr  public.company_deposit_addresses;
    v_row   public.deposit_requests;
BEGIN
    v_uid := public.fx_require_user_id();

    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_row FROM public.deposit_requests
        WHERE user_id = v_uid AND request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate', 'deposit', public.fx_deposit_public_json(v_row));
        END IF;
    END IF;

    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    IF p_amount IS NULL OR p_amount < COALESCE(v_cfg.min_deposit_usd, 10) THEN
        RAISE EXCEPTION 'AMOUNT_TOO_SMALL: the minimum deposit is % USD', COALESCE(v_cfg.min_deposit_usd, 10)
            USING ERRCODE = '22023';
    END IF;
    IF p_amount >= 100000000000000 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: deposit amount is out of range' USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('fx_deposit_request:' || v_uid));

    v_addr := public.fx_assign_deposit_address();

    -- Resume the user's open, not-yet-submitted request on the CURRENT address.
    SELECT * INTO v_row FROM public.deposit_requests
    WHERE user_id = v_uid AND status = 'PENDING'
      AND verification_status IN ('NOT_REQUIRED', 'WAITING')
      AND proof_path IS NULL AND txid IS NULL
      AND address_used = v_addr.address
      AND created_at > NOW() - INTERVAL '24 hours'
    ORDER BY created_at DESC LIMIT 1;
    IF FOUND THEN
        IF v_row.amount_claimed <> ROUND(p_amount, 4) THEN
            UPDATE public.deposit_requests SET amount_claimed = ROUND(p_amount, 4), updated_at = NOW()
             WHERE id = v_row.id RETURNING * INTO v_row;
        END IF;
        RETURN jsonb_build_object('status', 'existing', 'deposit', public.fx_deposit_public_json(v_row));
    END IF;

    IF (SELECT COUNT(*) FROM public.deposit_requests WHERE user_id = v_uid AND status = 'PENDING') >= 5 THEN
        RAISE EXCEPTION 'TOO_MANY_PENDING: you already have deposits awaiting review' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.deposit_requests
        (user_id, amount_claimed, txid, deposit_address, address_used, verification_status, request_id)
    VALUES
        (v_uid, ROUND(p_amount, 4), NULL, v_addr.address, v_addr.address, 'NOT_REQUIRED', p_request_id)
    RETURNING * INTO v_row;

    RETURN jsonb_build_object('status', 'success', 'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
