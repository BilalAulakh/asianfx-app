-- ==============================================================================
-- MIGRATION: 20261006000200_admin_address_a.sql
--
-- The admin's "Company Deposit Wallet" field sets ADDRESS A of the rotation.
--
-- rpc_admin_set_deposit_address(p_address) (the RPC that field already calls):
--   * makes p_address the manual rotation address: weight 3, auto_verify = false,
--     first in order -> it receives requests 1, 2, 3 of every 4;
--   * deactivates the previous manual address(es) - kept for history;
--   * leaves the automatic Address B (TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS) as is,
--     so B still receives every 4th request: A, A, A, B, A, A, A, B, ...;
--   * mirrors the address into broker_config.deposit_address_trc20 (used by the
--     one-shot claim of older app builds);
--   * is audited in admin_config_audit.
--
-- Runs under the rotation lock so a request in flight never sees a half-applied
-- change. Requires 20261006000100_auto_verify_deposits.sql. Idempotent.
-- ==============================================================================

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

    -- Serialise with fx_assign_deposit_address().
    PERFORM 1 FROM public.deposit_rotation_state WHERE id = 1 FOR UPDATE;

    IF EXISTS (SELECT 1 FROM public.company_deposit_addresses WHERE address = v_new AND auto_verify) THEN
        RAISE EXCEPTION 'ADDRESS_IS_AUTOMATIC: % is the automatic Address B; choose a different address for Address A', v_new
            USING ERRCODE = '22023';
    END IF;

    SELECT address INTO v_old
    FROM public.company_deposit_addresses
    WHERE is_active AND NOT auto_verify AND weight > 0
    ORDER BY sort_order, created_at
    LIMIT 1;

    -- Previous manual addresses leave the rotation (rows kept for audit/history).
    UPDATE public.company_deposit_addresses
       SET is_active = FALSE, updated_at = NOW()
     WHERE NOT auto_verify AND address <> v_new AND is_active;

    INSERT INTO public.company_deposit_addresses
        (address, label, weight, sort_order, is_active, auto_verify, max_auto_approve_usd)
    VALUES (v_new, 'Address A (manual)', 3, 0, TRUE, FALSE, 1000)
    ON CONFLICT (address) DO UPDATE
        SET label = 'Address A (manual)', weight = 3, sort_order = 0,
            is_active = TRUE, auto_verify = FALSE, updated_at = NOW();

    -- Keep every automatic address after A in the rotation order.
    UPDATE public.company_deposit_addresses
       SET sort_order = GREATEST(sort_order, 1), updated_at = NOW()
     WHERE auto_verify AND sort_order < 1;

    UPDATE public.broker_config
       SET deposit_address_trc20 = v_new, updated_at = NOW()
     WHERE id = 1;

    IF v_old IS DISTINCT FROM v_new THEN
        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_address_a', 'company_deposit_addresses',
                jsonb_build_object('address_a', v_old),
                jsonb_build_object('address_a', v_new));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'deposit_address', v_new, 'previous', v_old);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
