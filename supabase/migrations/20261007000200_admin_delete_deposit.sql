-- ==============================================================================
-- MIGRATION: 20261007000200_admin_delete_deposit.sql
--
-- Admins can delete a deposit request that never moved money:
--   * PENDING  (not paid / not reviewed yet, including automatic ones), or
--   * REJECTED.
-- APPROVED deposits are refused: their amount is already in the user's wallet
-- and the double-entry ledger references them, so deleting the request would
-- break the audit trail. (Correct a wrong credit with a balance adjustment.)
--
-- Every deletion is audited in admin_config_audit with the full deleted row.
-- The RPC returns the screenshot path; the app then removes the file from the
-- deposit-proofs bucket (admins get a DELETE policy on that bucket below).
--
-- Idempotent.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_delete_deposit_request(
    p_deposit_id UUID,
    p_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_d     public.deposit_requests;
BEGIN
    v_admin := public.fx_require_admin();

    SELECT * INTO v_d FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: this deposit request no longer exists' USING ERRCODE = '22023';
    END IF;
    IF v_d.status = 'APPROVED' THEN
        RAISE EXCEPTION 'DEPOSIT_CREDITED: an approved deposit was already credited to the wallet and cannot be deleted'
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.deposit_requests WHERE id = p_deposit_id;

    INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
    VALUES (v_admin, 'delete_deposit_request', p_deposit_id::TEXT, to_jsonb(v_d),
            jsonb_build_object('reason', NULLIF(left(btrim(COALESCE(p_reason, '')), 500), '')));

    RETURN jsonb_build_object('status', 'success', 'deleted', p_deposit_id, 'proof_path', v_d.proof_path);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_delete_deposit_request(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_admin_delete_deposit_request(UUID, TEXT) TO authenticated;

-- Admins may remove payment screenshots (used after deleting a request).
DO $$
BEGIN
    DROP POLICY IF EXISTS "deposit_proofs_delete_admin" ON storage.objects;
    CREATE POLICY "deposit_proofs_delete_admin" ON storage.objects
        FOR DELETE TO authenticated
        USING (bucket_id = 'deposit-proofs' AND (SELECT public.fx_is_admin()));
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'storage policy not created (%); screenshots of deleted requests stay in the bucket', SQLERRM;
END $$;

NOTIFY pgrst, 'reload schema';
