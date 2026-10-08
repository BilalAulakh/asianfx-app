-- ==============================================================================
-- MIGRATION: 20261008000200_user_delete_deposit.sql
--
-- Users can remove their own deposit requests from "My deposit requests":
--   * PENDING, still awaiting payment (no screenshot, no TXID): deleted outright
--     (nothing was paid or claimed yet).
--   * PENDING with a screenshot / TXID (under review): refused, the admin or the
--     automatic verifier is working on it.
--   * APPROVED / REJECTED: hidden from the user's list only (user_hidden_at).
--     The row stays for the ledger, the admin desk and the one-claim-per-TXID
--     rule, so a rejected TXID can never be claimed again.
--
-- Idempotent.
-- ==============================================================================

ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS user_hidden_at TIMESTAMPTZ;

-- Clients read deposit_requests through a column-level grant: the app filters
-- its list on this column, so depositors must be allowed to read it.
GRANT SELECT (user_hidden_at) ON public.deposit_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_delete_my_deposit_request(p_deposit_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid TEXT;
    v_d   public.deposit_requests;
BEGIN
    v_uid := public.fx_require_user_id();

    SELECT * INTO v_d FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND OR v_d.user_id <> v_uid THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no such deposit request' USING ERRCODE = '22023';
    END IF;

    IF v_d.status = 'PENDING' THEN
        IF v_d.proof_path IS NOT NULL OR v_d.txid IS NOT NULL THEN
            RAISE EXCEPTION 'UNDER_REVIEW: this deposit is being reviewed and cannot be deleted'
                USING ERRCODE = '22023';
        END IF;
        DELETE FROM public.deposit_requests WHERE id = p_deposit_id;
        RETURN jsonb_build_object('status', 'success', 'action', 'deleted', 'id', p_deposit_id);
    END IF;

    UPDATE public.deposit_requests SET user_hidden_at = COALESCE(user_hidden_at, NOW())
     WHERE id = p_deposit_id;
    RETURN jsonb_build_object('status', 'success', 'action', 'hidden', 'id', p_deposit_id);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_delete_my_deposit_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_delete_my_deposit_request(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
