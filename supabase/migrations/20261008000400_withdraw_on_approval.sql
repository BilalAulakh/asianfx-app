-- ==============================================================================
-- MIGRATION: 20261008000400_withdraw_on_approval.sql
--
-- Withdrawals are deducted from the balance when the admin APPROVES them, not
-- when the user asks.
--
--   rpc_request_withdrawal      checks the amount and records the request; the
--                               wallet is NOT touched. Requests still pending
--                               are reserved, so a $100 balance cannot have two
--                               $100 requests open at once.
--   rpc_admin_review_withdrawal approve: re-checks balance and free margin NOW
--                               and deducts (refused if the user no longer has
--                               the money: do not pay, reject instead).
--                               reject: nothing to return, the balance was
--                               never touched.
--
-- Requests made before this migration were already deducted at request time
-- (funds_held = TRUE): they keep the old behaviour (approve = record only,
-- reject = refund), so no balance is ever charged twice or refunded wrongly.
--
-- The legacy rpc_review_withdrawal (no payout TXID, unused by the app) is
-- withdrawn from clients so the only review path follows these rules.
--
-- Idempotent.
-- ==============================================================================

ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS funds_held BOOLEAN NOT NULL DEFAULT TRUE;

-- ------------------------------------------------------------------------------
-- USER: request (no deduction)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_request_withdrawal(
    p_amount      NUMERIC,
    p_method      TEXT DEFAULT NULL,
    p_destination TEXT DEFAULT NULL,
    p_request_id  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid     TEXT;
    v_cfg     public.broker_config;
    v_wallet  public.wallets;
    v_unreal  NUMERIC;
    v_free    NUMERIC;
    v_pending NUMERIC;
    v_avail   NUMERIC;
    v_id      UUID;
    v_kyc     TEXT;
    v_prev    public.withdrawals;
BEGIN
    v_uid := public.fx_require_user_id();
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: withdrawal amount must be positive' USING ERRCODE = '22023';
    END IF;

    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.withdrawals WHERE request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate', 'withdrawal_id', v_prev.id,
                                      'withdrawal_status', v_prev.status);
        END IF;
    END IF;

    IF v_cfg.require_kyc_for_withdraw AND public.fx_kyc_module_installed() THEN
        v_kyc := public.fx_kyc_status(v_uid);
        IF COALESCE(v_kyc, 'NOT_STARTED') <> 'APPROVED' THEN
            RAISE EXCEPTION 'KYC_REQUIRED: withdrawals require approved identity verification'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Lock the wallet so two requests cannot both pass the check below.
    v_wallet := public.fx_lock_wallet(v_uid);
    v_unreal := public.fx_unrealized_total(v_uid, NULL);
    v_free   := (v_wallet.balance + v_unreal) - v_wallet.held_margin;

    -- Pending requests not yet deducted are reserved against new ones.
    SELECT COALESCE(SUM(amount), 0) INTO v_pending FROM public.withdrawals
     WHERE user_id = v_uid AND status = 'PENDING' AND NOT funds_held;
    v_avail := LEAST(v_wallet.balance, v_free) - v_pending;

    IF v_avail < p_amount THEN
        RAISE EXCEPTION
            'INSUFFICIENT_FUNDS: withdrawable amount is % (balance %, free margin %, pending withdrawals %)',
            ROUND(GREATEST(v_avail, 0), 2), ROUND(v_wallet.balance, 2), ROUND(v_free, 2), ROUND(v_pending, 2)
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.withdrawals (user_id, amount, method, destination, request_id, funds_held)
    VALUES (v_uid, p_amount, p_method, p_destination, p_request_id, FALSE)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'status', 'success',
        'withdrawal_id', v_id,
        'withdrawal_status', 'PENDING',
        'amount', p_amount,
        'balance_after', v_wallet.balance,
        'pending_withdrawals', v_pending + p_amount);
END;
$$;

-- ------------------------------------------------------------------------------
-- ADMIN: review (deduct on approval)
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
    v_wallet public.wallets;
    v_unreal NUMERIC;
    v_free   NUMERIC;
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

    v_note   := NULLIF(btrim(COALESCE(p_admin_note, '')), '');
    v_wallet := public.fx_lock_wallet(v_w.user_id);

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

        IF v_w.funds_held THEN
            -- Old request: the amount was deducted when it was made.
            v_new := v_wallet.balance;
        ELSE
            v_unreal := public.fx_unrealized_total(v_w.user_id, NULL);
            v_free   := (v_wallet.balance + v_unreal) - v_wallet.held_margin;
            IF v_wallet.balance < v_w.amount OR v_free < v_w.amount THEN
                RAISE EXCEPTION
                    'INSUFFICIENT_FUNDS: the user now has balance % and free margin %, less than this % withdrawal. Do not pay it: reject it instead.',
                    ROUND(v_wallet.balance, 2), ROUND(v_free, 2), ROUND(v_w.amount, 2)
                    USING ERRCODE = '22023';
            END IF;
            v_new := v_wallet.balance - v_w.amount;
            UPDATE public.wallets SET balance = v_new, updated_at = NOW()
             WHERE user_id = v_w.user_id AND currency = 'USD';
        END IF;

        UPDATE public.withdrawals
           SET status = 'APPROVED', reviewed_by = v_admin, reviewed_at = NOW(),
               payout_txid = v_txid, admin_note = v_note, updated_at = NOW()
         WHERE id = p_withdrawal_id
        RETURNING * INTO v_w;

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

    IF v_w.funds_held THEN
        -- Old request: return the amount deducted at request time.
        v_new := v_wallet.balance + v_w.amount;
        UPDATE public.wallets SET balance = v_new, updated_at = NOW()
         WHERE user_id = v_w.user_id AND currency = 'USD';
        PERFORM public.fx_post_ledger(
            v_w.user_id, 'withdrawal_refund', v_w.amount, v_new, p_withdrawal_id::TEXT,
            format('Withdrawal rejected by %s: %s', v_admin, btrim(p_reason)),
            'withdrawal_refund:' || p_withdrawal_id::TEXT);
    ELSE
        v_new := v_wallet.balance; -- nothing was deducted
    END IF;

    UPDATE public.withdrawals
       SET status = 'REJECTED', reviewed_by = v_admin, reviewed_at = NOW(),
           reject_reason = btrim(p_reason), admin_note = v_note, updated_at = NOW()
     WHERE id = p_withdrawal_id
    RETURNING * INTO v_w;

    RETURN jsonb_build_object('status', 'success', 'withdrawal', to_jsonb(v_w), 'balance_after', v_new);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_review_withdrawal(UUID, BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_review_withdrawal(UUID, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

-- Legacy review path (deducted-at-request only, no payout TXID): not used by the app.
REVOKE ALL ON FUNCTION public.rpc_review_withdrawal(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
