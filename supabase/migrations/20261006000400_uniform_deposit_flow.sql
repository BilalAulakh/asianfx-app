-- ==============================================================================
-- MIGRATION: 20261006000400_uniform_deposit_flow.sql
--
-- Users see ONE deposit flow, whatever address the rotation assigned:
-- get address -> pay -> attach screenshot -> under review -> approved.
-- Automatic (Address B) handling stays entirely server-side.
--
--   rpc_attach_deposit_proof: also accepts a screenshot while the request is
--     WAITING for automatic verification. It stays WAITING (the verifier still
--     credits it automatically, hidden from admins); if verification fails or
--     times out, the admin reviews it with the screenshot attached.
--   rpc_create_deposit_request: an open request is resumed only while it still
--     has no screenshot (manual or automatic alike), so after "I have sent the
--     payment" the user can start a new deposit.
--
-- Requires 20261006000100_auto_verify_deposits.sql. Idempotent.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_attach_deposit_proof(
    p_deposit_id UUID,
    p_proof_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid   TEXT;
    v_row   public.deposit_requests;
    v_proof TEXT;
BEGIN
    v_uid := public.fx_require_user_id();

    SELECT * INTO v_row FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND OR v_row.user_id <> v_uid THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no such deposit request' USING ERRCODE = '22023';
    END IF;
    IF v_row.status <> 'PENDING' THEN
        RAISE EXCEPTION 'ALREADY_REVIEWED: this deposit was already %', lower(v_row.status) USING ERRCODE = '22023';
    END IF;

    v_proof := NULLIF(btrim(COALESCE(p_proof_path, '')), '');
    IF v_proof IS NULL THEN
        RAISE EXCEPTION 'PROOF_REQUIRED: please attach a screenshot of your payment' USING ERRCODE = '22023';
    END IF;
    IF left(v_proof, length(v_uid) + 1) <> v_uid || '/' OR position('..' IN v_proof) > 0 OR length(v_proof) > 512 THEN
        RAISE EXCEPTION 'BAD_PROOF_PATH: the payment proof must be uploaded to your own folder' USING ERRCODE = '42501';
    END IF;

    -- verification_status is left as is: WAITING requests keep being verified
    -- automatically; NOT_REQUIRED ones now appear in the admin Pending queue.
    UPDATE public.deposit_requests SET proof_path = v_proof, updated_at = NOW()
     WHERE id = p_deposit_id RETURNING * INTO v_row;

    RETURN jsonb_build_object('status', 'success', 'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

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

    -- Resume the user's open, not-yet-submitted request (no screenshot yet), on
    -- any address: no extra rotation slot is consumed. The amount may be corrected.
    SELECT * INTO v_row FROM public.deposit_requests
    WHERE user_id = v_uid AND status = 'PENDING'
      AND verification_status IN ('NOT_REQUIRED', 'WAITING')
      AND proof_path IS NULL AND txid IS NULL
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

    v_addr := public.fx_assign_deposit_address();

    INSERT INTO public.deposit_requests
        (user_id, amount_claimed, txid, deposit_address, address_used, verification_status, request_id)
    VALUES
        (v_uid, ROUND(p_amount, 4), NULL, v_addr.address, v_addr.address,
         CASE WHEN v_addr.auto_verify THEN 'WAITING' ELSE 'NOT_REQUIRED' END, p_request_id)
    RETURNING * INTO v_row;

    RETURN jsonb_build_object('status', 'success', 'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_attach_deposit_proof(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_attach_deposit_proof(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
