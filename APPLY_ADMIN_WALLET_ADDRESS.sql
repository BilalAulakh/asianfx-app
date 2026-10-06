-- APPLY_ADMIN_WALLET_ADDRESS.sql: paste into the Supabase SQL Editor and Run.
-- Copy of supabase/migrations/20261005000100_admin_deposit_address.sql

-- ==============================================================================
-- MIGRATION: 20261005000100_admin_deposit_address.sql
--
-- Lets an administrator change the company USDT (TRC-20) deposit address from
-- Admin > Finance Desk > USDT Deposits, instead of editing SQL.
--
--   * Only administrators (fx_require_admin) may call it.
--   * Only a syntactically valid base58 TRON address is accepted (T + 33 chars,
--     no 0 / O / I / l) — the same rule as broker_config's CHECK constraint.
--   * Every change is written to admin_config_audit (who, old, new, when).
--
-- Every user's deposit screen reads broker_config.deposit_address_trc20, and
-- rpc_submit_deposit_request records it on each claim, so the change applies
-- to all new deposits immediately. Idempotent; safe to re-run.
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

    SELECT deposit_address_trc20 INTO v_old FROM public.broker_config WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_CONFIGURED: broker_config row 1 is missing' USING ERRCODE = '22023';
    END IF;

    IF v_old IS DISTINCT FROM v_new THEN
        UPDATE public.broker_config
           SET deposit_address_trc20 = v_new, updated_at = NOW()
         WHERE id = 1;

        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_deposit_address', 'broker_config',
                jsonb_build_object('deposit_address_trc20', v_old),
                jsonb_build_object('deposit_address_trc20', v_new));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'deposit_address', v_new, 'previous', v_old);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) FROM PUBLIC, anon;
-- Admin-gated inside the function (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_deposit_address(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
