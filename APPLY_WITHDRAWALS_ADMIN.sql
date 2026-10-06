-- APPLY_WITHDRAWALS_ADMIN.sql: paste into the Supabase SQL Editor and Run.
-- Copy of supabase/migrations/20261006000000_admin_withdrawals.sql

-- ==============================================================================
-- MIGRATION: 20261006000000_admin_withdrawals.sql
--
-- Server-backed withdrawal review for Admin > Finance Desk > Withdrawals.
--
-- Until now the admin screen showed a client-side copy of each withdrawal and
-- its Approve / Reject buttons never reached the database: the user's funds
-- stayed held forever and nothing recorded what was actually paid.
--
--   rpc_admin_list_withdrawals   queue + everything needed to decide: user,
--                                KYC, current balance, exposure, history
--   rpc_admin_review_withdrawal  approve (payout TXID required) / reject
--                                (reason required; held funds returned)
--
-- rpc_request_withdrawal (unchanged) already deducts and holds the amount the
-- moment the user asks. Idempotent; safe to re-run.
-- ==============================================================================

ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS payout_txid TEXT;
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS admin_note  TEXT;

-- One on-chain payment settles exactly one withdrawal.
CREATE UNIQUE INDEX IF NOT EXISTS uq_withdrawals_payout_txid
    ON public.withdrawals (lower(payout_txid)) WHERE payout_txid IS NOT NULL;

-- ------------------------------------------------------------------------------
-- ADMIN QUEUE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_list_withdrawals(
    p_status TEXT    DEFAULT NULL,
    p_limit  INTEGER DEFAULT 200
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v_out JSONB;
BEGIN
    PERFORM public.fx_require_admin();

    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.is_pending DESC, x.created_at DESC), '[]'::JSONB)
      INTO v_out
    FROM (
        SELECT
            to_jsonb(w) || jsonb_build_object(
                'user_email',        u.email,
                'user_created_at',   u.created_at,
                'last_sign_in_at',   u.last_sign_in_at,
                'full_name',         NULLIF(btrim(concat_ws(' ', k.first_name, k.last_name)), ''),
                'kyc_status',        COALESCE(k.status, 'NOT_STARTED'),
                'wallet_balance',    wl.balance,
                'held_margin',       wl.held_margin,
                'open_positions',    (SELECT COUNT(*) FROM public.trades t
                                       WHERE t.user_id = w.user_id AND t.status = 'open'),
                'realized_pnl_total',(SELECT COALESCE(SUM(t.realized_pnl), 0) FROM public.trades t
                                       WHERE t.user_id = w.user_id AND t.status IN ('closed', 'liquidated')),
                'total_deposited',   (SELECT COALESCE(SUM(d.amount_credited), 0) FROM public.deposit_requests d
                                       WHERE d.user_id = w.user_id AND d.status = 'APPROVED'),
                'total_withdrawn',   (SELECT COALESCE(SUM(o.amount), 0) FROM public.withdrawals o
                                       WHERE o.user_id = w.user_id AND o.status = 'APPROVED'),
                'previous_withdrawals', (SELECT COUNT(*) FROM public.withdrawals o
                                       WHERE o.user_id = w.user_id AND o.id <> w.id)
            ) AS j,
            (w.status = 'PENDING') AS is_pending,
            w.created_at
        FROM public.withdrawals w
        LEFT JOIN auth.users u            ON u.id::TEXT = w.user_id
        LEFT JOIN public.kyc_profiles k   ON k.user_id = w.user_id
        LEFT JOIN public.wallets wl       ON wl.user_id = w.user_id AND wl.currency = 'USD'
        WHERE p_status IS NULL OR w.status = upper(p_status)
        ORDER BY (w.status = 'PENDING') DESC, w.created_at DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
    ) x;

    RETURN v_out;
END;
$$;

-- ------------------------------------------------------------------------------
-- ADMIN REVIEW
-- Approve = the admin has already sent the USDT and records the on-chain TXID.
-- Reject  = a written reason is required; the held amount goes back to the user.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_review_withdrawal(
    p_withdrawal_id UUID,
    p_approve       BOOLEAN,
    p_reason        TEXT DEFAULT NULL,
    p_payout_txid   TEXT DEFAULT NULL,
    p_admin_note    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin  TEXT;
    v_caller TEXT;
    v_w      public.withdrawals;
    v_new    NUMERIC;
    v_txid   TEXT;
    v_note   TEXT;
BEGIN
    v_admin  := public.fx_require_admin();
    v_caller := public.fx_auth_user_id();

    IF p_approve IS NULL THEN
        RAISE EXCEPTION 'BAD_DECISION: p_approve must be true or false' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_w FROM public.withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'WITHDRAWAL_NOT_FOUND: no withdrawal %', p_withdrawal_id USING ERRCODE = '22023';
    END IF;

    -- Four-eyes rule: nobody pays out their own withdrawal.
    IF v_caller IS NOT NULL AND v_caller = v_w.user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: an administrator cannot review their own withdrawal'
            USING ERRCODE = '42501';
    END IF;

    -- Second click / second admin: return the existing verdict, move nothing.
    IF v_w.status <> 'PENDING' THEN
        RETURN jsonb_build_object('status', 'already_reviewed', 'withdrawal', to_jsonb(v_w),
                                  'message', format('This withdrawal was already %s.', lower(v_w.status)));
    END IF;

    v_note := NULLIF(btrim(COALESCE(p_admin_note, '')), '');
    PERFORM public.fx_lock_wallet(v_w.user_id);

    IF p_approve THEN
        v_txid := lower(btrim(COALESCE(p_payout_txid, '')));
        IF v_txid !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'BAD_TXID: enter the 64-character TRON transaction ID of the payment you sent'
                USING ERRCODE = '22023';
        END IF;
        IF EXISTS (SELECT 1 FROM public.withdrawals WHERE lower(payout_txid) = v_txid) THEN
            RAISE EXCEPTION 'TXID_ALREADY_USED: this payment TXID is already recorded on another withdrawal'
                USING ERRCODE = '23505';
        END IF;

        UPDATE public.withdrawals
           SET status = 'APPROVED', reviewed_by = v_admin, reviewed_at = NOW(),
               payout_txid = v_txid, admin_note = v_note, updated_at = NOW()
         WHERE id = p_withdrawal_id
        RETURNING * INTO v_w;

        SELECT balance INTO v_new FROM public.wallets
        WHERE user_id = v_w.user_id AND currency = 'USD';

        PERFORM public.fx_post_ledger(
            v_w.user_id, 'withdrawal', -v_w.amount, v_new, p_withdrawal_id::TEXT,
            format('Withdrawal paid by %s (txid %s)', v_admin, v_txid),
            'withdrawal:' || p_withdrawal_id::TEXT);

        RETURN jsonb_build_object('status', 'success', 'withdrawal', to_jsonb(v_w), 'balance_after', v_new);
    END IF;

    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'REASON_REQUIRED: a written reason is required to reject a withdrawal'
            USING ERRCODE = '22023';
    END IF;

    SELECT balance + v_w.amount INTO v_new FROM public.wallets
    WHERE user_id = v_w.user_id AND currency = 'USD';

    UPDATE public.wallets SET balance = v_new, updated_at = NOW()
     WHERE user_id = v_w.user_id AND currency = 'USD';

    UPDATE public.withdrawals
       SET status = 'REJECTED', reviewed_by = v_admin, reviewed_at = NOW(),
           reject_reason = btrim(p_reason), admin_note = v_note, updated_at = NOW()
     WHERE id = p_withdrawal_id
    RETURNING * INTO v_w;

    PERFORM public.fx_post_ledger(
        v_w.user_id, 'withdrawal_refund', v_w.amount, v_new, p_withdrawal_id::TEXT,
        format('Withdrawal rejected by %s: %s', v_admin, btrim(p_reason)),
        'withdrawal_refund:' || p_withdrawal_id::TEXT);

    RETURN jsonb_build_object('status', 'success', 'withdrawal', to_jsonb(v_w), 'balance_after', v_new);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_list_withdrawals(TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_review_withdrawal(UUID, BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
-- Admin-gated inside the functions (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_list_withdrawals(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_review_withdrawal(UUID, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
