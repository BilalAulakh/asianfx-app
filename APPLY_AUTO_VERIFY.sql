-- APPLY_AUTO_VERIFY.sql: paste into the Supabase SQL Editor and Run (after APPLY_WITHDRAWALS_ADMIN.sql).
-- Copies of supabase/migrations/20261006000100_auto_verify_deposits.sql
--        and supabase/migrations/20261006000200_admin_address_a.sql

-- ==============================================================================
-- MIGRATION: 20261006000100_auto_verify_deposits.sql
--
-- Weighted company-address rotation + automatic on-chain approval.
--
--   company_deposit_addresses   the company's USDT (TRC-20) receiving addresses,
--                               each with a rotation weight, auto_verify flag and
--                               max_auto_approve_usd
--   deposit_rotation_state      one counter row; locked FOR UPDATE so concurrent
--                               requests never share a slot (A,A,A,B,A,A,A,B,...)
--
-- New deposit flow (address is assigned BEFORE the user sends anything):
--   rpc_create_deposit_request  amount -> server assigns an address by rotation,
--                               stores it in deposit_requests.address_used
--   * auto_verify = false (A):  user sends, then rpc_attach_deposit_proof
--                               (screenshot) -> admin Pending -> rpc_review_deposit
--   * auto_verify = true  (B):  verification_status = WAITING, hidden from admin;
--                               auto-verify-deposits (Edge Function, every minute)
--                               finds the confirmed TronGrid transfer and calls
--                               rpc_system_approve_deposit (credits the ON-CHAIN
--                               amount) or rpc_system_mark_verification (FAILED ->
--                               admin Pending with a reason).
--
-- rpc_submit_deposit_request (one-shot claim used by older app builds, filed
-- AFTER the user already sent funds to broker_config.deposit_address_trc20) is
-- deliberately NOT rotated: rotating there could record a different address
-- from the one the user paid. Those claims stay manual (NOT_REQUIRED).
--
-- Additive and idempotent. No earlier migration is modified.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. COMPANY DEPOSIT ADDRESSES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_deposit_addresses (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address              TEXT          NOT NULL UNIQUE
                         CHECK (address ~ '^T[1-9A-HJ-NP-Za-km-z]{33}$'),
    label                TEXT,
    weight               INTEGER       NOT NULL DEFAULT 1 CHECK (weight BETWEEN 0 AND 100),
    sort_order           INTEGER       NOT NULL DEFAULT 0,
    is_active            BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE public.company_deposit_addresses
    ADD COLUMN IF NOT EXISTS auto_verify BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.company_deposit_addresses
    ADD COLUMN IF NOT EXISTS max_auto_approve_usd NUMERIC(18, 4) NOT NULL DEFAULT 1000;
ALTER TABLE public.company_deposit_addresses DROP CONSTRAINT IF EXISTS company_deposit_addresses_max_auto_check;
ALTER TABLE public.company_deposit_addresses ADD CONSTRAINT company_deposit_addresses_max_auto_check
    CHECK (max_auto_approve_usd >= 0);

ALTER TABLE public.company_deposit_addresses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.company_deposit_addresses FROM anon, authenticated;

-- Address A: manual, 3 of every 4 requests. Address B: automatic, 1 of every 4.
-- Re-running keeps admin-edited labels/active flags; only the business-rule
-- fields named by the spec are (re)asserted.
INSERT INTO public.company_deposit_addresses (address, label, weight, sort_order, auto_verify, max_auto_approve_usd)
VALUES ('TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'Address A (manual)',    3, 1, FALSE, 1000),
       ('TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS', 'Address B (automatic)', 1, 2, TRUE,  1000)
ON CONFLICT (address) DO UPDATE
    SET weight = EXCLUDED.weight,
        sort_order = EXCLUDED.sort_order,
        auto_verify = EXCLUDED.auto_verify,
        max_auto_approve_usd = EXCLUDED.max_auto_approve_usd,
        updated_at = NOW();

-- ------------------------------------------------------------------------------
-- 2. ROTATION STATE + ATOMIC ASSIGNMENT
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposit_rotation_state (
    id       SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    counter  BIGINT   NOT NULL DEFAULT 0
);
INSERT INTO public.deposit_rotation_state (id, counter) VALUES (1, 0) ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.deposit_rotation_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.deposit_rotation_state FROM anon, authenticated;

-- Next address in weighted round-robin order. Slots are laid out by sort_order:
-- weights A=3, B=1 give A,A,A,B, then repeat. The state row is locked, so two
-- concurrent callers always get consecutive, distinct slots.
CREATE OR REPLACE FUNCTION public.fx_assign_deposit_address()
RETURNS public.company_deposit_addresses
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_counter BIGINT;
    v_total   INTEGER;
    v_slot    INTEGER;
    v_acc     INTEGER := 0;
    v_row     public.company_deposit_addresses;
BEGIN
    SELECT counter INTO v_counter FROM public.deposit_rotation_state WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO public.deposit_rotation_state (id, counter) VALUES (1, 0)
        ON CONFLICT (id) DO NOTHING;
        SELECT counter INTO v_counter FROM public.deposit_rotation_state WHERE id = 1 FOR UPDATE;
    END IF;

    SELECT COALESCE(SUM(weight), 0) INTO v_total
    FROM public.company_deposit_addresses WHERE is_active AND weight > 0;
    IF v_total = 0 THEN
        RAISE EXCEPTION 'DEPOSITS_DISABLED: no active company deposit address. Please contact support.'
            USING ERRCODE = '22023';
    END IF;

    v_slot := (v_counter % v_total)::INTEGER;
    FOR v_row IN
        SELECT * FROM public.company_deposit_addresses
        WHERE is_active AND weight > 0
        ORDER BY sort_order, created_at, address
    LOOP
        v_acc := v_acc + v_row.weight;
        EXIT WHEN v_slot < v_acc;
    END LOOP;

    UPDATE public.deposit_rotation_state SET counter = v_counter + 1 WHERE id = 1;
    RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.fx_assign_deposit_address() FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. DEPOSIT REQUEST COLUMNS
-- ------------------------------------------------------------------------------
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS address_used          TEXT;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS verification_status   TEXT NOT NULL DEFAULT 'NOT_REQUIRED';
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS verification_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS last_verified_at      TIMESTAMPTZ;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS verification_error    TEXT;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS onchain_amount        NUMERIC(18, 4);
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS onchain_to            TEXT;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS onchain_from          TEXT;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS onchain_block         BIGINT;
ALTER TABLE public.deposit_requests ADD COLUMN IF NOT EXISTS approved_by_system    BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.deposit_requests DROP CONSTRAINT IF EXISTS deposit_requests_verification_status_check;
ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_verification_status_check
    CHECK (verification_status IN ('NOT_REQUIRED', 'WAITING', 'VERIFIED', 'FAILED'));

-- Older rows: the address shown at submit time was recorded in deposit_address.
UPDATE public.deposit_requests SET address_used = deposit_address
 WHERE address_used IS NULL AND deposit_address IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_deposit_requests_waiting
    ON public.deposit_requests (created_at) WHERE status = 'PENDING' AND verification_status = 'WAITING';
CREATE INDEX IF NOT EXISTS idx_deposit_requests_auto_approved
    ON public.deposit_requests (reviewed_at DESC) WHERE approved_by_system;

-- Depositors may read the verification outcome of their own requests.
GRANT SELECT (address_used, verification_status, verification_error, onchain_amount,
              approved_by_system, last_verified_at)
    ON public.deposit_requests TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. USER: CREATE A REQUEST (address assigned by rotation)
-- ------------------------------------------------------------------------------
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

    -- One open request per user: an unfunded manual request (no proof yet) or
    -- one still being verified is returned instead of burning another rotation
    -- slot. The amount of an unfunded manual request can still be corrected.
    SELECT * INTO v_row FROM public.deposit_requests
    WHERE user_id = v_uid AND status = 'PENDING'
      AND ((verification_status = 'NOT_REQUIRED' AND proof_path IS NULL AND txid IS NULL)
           OR verification_status = 'WAITING')
      AND created_at > NOW() - INTERVAL '24 hours'
    ORDER BY created_at DESC LIMIT 1;
    IF FOUND THEN
        IF v_row.verification_status = 'NOT_REQUIRED' AND v_row.amount_claimed <> ROUND(p_amount, 4) THEN
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

-- ------------------------------------------------------------------------------
-- 5. USER: ATTACH THE PAYMENT SCREENSHOT (manual addresses)
-- ------------------------------------------------------------------------------
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
    IF v_row.verification_status = 'WAITING' THEN
        RAISE EXCEPTION 'AUTO_VERIFY_IN_PROGRESS: this deposit is being verified on the blockchain automatically'
            USING ERRCODE = '22023';
    END IF;

    v_proof := NULLIF(btrim(COALESCE(p_proof_path, '')), '');
    IF v_proof IS NULL THEN
        RAISE EXCEPTION 'PROOF_REQUIRED: please attach a screenshot of your payment' USING ERRCODE = '22023';
    END IF;
    IF left(v_proof, length(v_uid) + 1) <> v_uid || '/' OR position('..' IN v_proof) > 0 OR length(v_proof) > 512 THEN
        RAISE EXCEPTION 'BAD_PROOF_PATH: the payment proof must be uploaded to your own folder' USING ERRCODE = '42501';
    END IF;

    UPDATE public.deposit_requests SET proof_path = v_proof, updated_at = NOW()
     WHERE id = p_deposit_id RETURNING * INTO v_row;

    RETURN jsonb_build_object('status', 'success', 'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. SYSTEM: AUTOMATIC APPROVAL (backend / service_role only)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_system_approve_deposit(
    p_deposit_id     UUID,
    p_txid           TEXT,
    p_onchain_amount NUMERIC,
    p_onchain_to     TEXT,
    p_onchain_from   TEXT,
    p_block          BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_d      public.deposit_requests;
    v_addr   public.company_deposit_addresses;
    v_wallet public.wallets;
    v_amount NUMERIC;
    v_new    NUMERIC;
    v_txid   TEXT;
BEGIN
    IF NOT public.fx_is_backend() THEN
        RAISE EXCEPTION 'FORBIDDEN: system approval is reserved for the backend' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_d FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no deposit request %', p_deposit_id USING ERRCODE = '22023';
    END IF;

    -- Idempotent: anything no longer PENDING + WAITING was already processed.
    IF v_d.status <> 'PENDING' OR v_d.verification_status <> 'WAITING' THEN
        RETURN jsonb_build_object('status', 'already_processed', 'deposit_status', v_d.status,
                                  'verification_status', v_d.verification_status);
    END IF;

    -- The recipient is the address the SERVER assigned, never caller-supplied.
    IF v_d.address_used IS NULL OR btrim(COALESCE(p_onchain_to, '')) <> v_d.address_used THEN
        UPDATE public.deposit_requests
           SET verification_status = 'FAILED', verification_error = 'WRONG_RECIPIENT',
               verification_attempts = verification_attempts + 1, last_verified_at = NOW(), updated_at = NOW()
         WHERE id = p_deposit_id;
        RETURN jsonb_build_object('status', 'failed', 'reason', 'WRONG_RECIPIENT');
    END IF;

    v_txid := lower(btrim(COALESCE(p_txid, '')));
    IF v_txid !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'BAD_TXID: a TRON transaction ID must be 64 hexadecimal characters' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.deposit_requests WHERE lower(txid) = v_txid AND id <> p_deposit_id) THEN
        RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction already settled another deposit' USING ERRCODE = '23505';
    END IF;

    v_amount := ROUND(COALESCE(p_onchain_amount, 0), 4);
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'ZERO_AMOUNT: on-chain amount must be positive' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_addr FROM public.company_deposit_addresses WHERE address = v_d.address_used;

    -- Above the automatic limit (or address no longer automatic): record what
    -- was found on-chain, credit nothing, hand over to an admin.
    IF v_addr.address IS NULL OR NOT v_addr.auto_verify OR v_amount > v_addr.max_auto_approve_usd THEN
        UPDATE public.deposit_requests
           SET verification_status = 'FAILED',
               verification_error  = CASE WHEN v_addr.address IS NOT NULL AND v_addr.auto_verify
                                          THEN 'ABOVE_AUTO_LIMIT' ELSE 'AUTO_VERIFY_DISABLED' END,
               txid = v_txid, onchain_amount = v_amount, onchain_to = v_d.address_used,
               onchain_from = NULLIF(btrim(COALESCE(p_onchain_from, '')), ''), onchain_block = p_block,
               verification_attempts = verification_attempts + 1, last_verified_at = NOW(), updated_at = NOW()
         WHERE id = p_deposit_id;
        RETURN jsonb_build_object('status', 'failed', 'reason',
            CASE WHEN v_addr.address IS NOT NULL AND v_addr.auto_verify THEN 'ABOVE_AUTO_LIMIT' ELSE 'AUTO_VERIFY_DISABLED' END);
    END IF;

    v_wallet := public.fx_lock_wallet(v_d.user_id);
    v_new    := v_wallet.balance + v_amount;

    UPDATE public.wallets SET balance = v_new, updated_at = NOW()
     WHERE user_id = v_d.user_id AND currency = 'USD';

    UPDATE public.deposit_requests
       SET status = 'APPROVED', verification_status = 'VERIFIED', approved_by_system = TRUE,
           reviewed_by = 'system:auto-verify', reviewed_at = NOW(),
           amount_credited = v_amount, txid = v_txid,
           onchain_amount = v_amount, onchain_to = v_d.address_used,
           onchain_from = NULLIF(btrim(COALESCE(p_onchain_from, '')), ''), onchain_block = p_block,
           verification_error = NULL, verification_attempts = verification_attempts + 1,
           last_verified_at = NOW(), updated_at = NOW()
     WHERE id = p_deposit_id
    RETURNING * INTO v_d;

    -- Same idempotency key as rpc_review_deposit: one deposit, one credit.
    PERFORM public.fx_post_ledger(
        v_d.user_id, 'deposit', v_amount, v_new, v_d.id::TEXT,
        format('USDT TRC20 deposit auto-verified on-chain (txid %s, block %s)', v_txid, p_block),
        'deposit:' || v_d.id::TEXT);

    RETURN jsonb_build_object('status', 'success', 'deposit_id', v_d.id, 'credited', v_amount, 'new_balance', v_new);
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. SYSTEM: RECORD A VERIFICATION ATTEMPT (backend / service_role only)
--    p_result = 'RETRY'  : not found yet / temporary error; stays WAITING
--    p_result = 'FAILED' : definitive (e.g. TIMEOUT); goes to admin Pending
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_system_mark_verification(
    p_deposit_id UUID,
    p_result     TEXT,
    p_error      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_d public.deposit_requests;
BEGIN
    IF NOT public.fx_is_backend() THEN
        RAISE EXCEPTION 'FORBIDDEN: verification updates are reserved for the backend' USING ERRCODE = '42501';
    END IF;
    IF upper(COALESCE(p_result, '')) NOT IN ('RETRY', 'FAILED') THEN
        RAISE EXCEPTION 'BAD_RESULT: p_result must be RETRY or FAILED' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_d FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no deposit request %', p_deposit_id USING ERRCODE = '22023';
    END IF;
    IF v_d.status <> 'PENDING' OR v_d.verification_status <> 'WAITING' THEN
        RETURN jsonb_build_object('status', 'already_processed');
    END IF;

    UPDATE public.deposit_requests
       SET verification_attempts = verification_attempts + 1,
           last_verified_at      = NOW(),
           verification_status   = CASE WHEN upper(p_result) = 'FAILED' THEN 'FAILED' ELSE verification_status END,
           verification_error    = CASE WHEN upper(p_result) = 'FAILED'
                                        THEN COALESCE(NULLIF(btrim(p_error), ''), 'UNKNOWN') ELSE verification_error END,
           updated_at            = NOW()
     WHERE id = p_deposit_id
    RETURNING * INTO v_d;

    RETURN jsonb_build_object('status', 'success', 'verification_status', v_d.verification_status,
                              'attempts', v_d.verification_attempts);
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. ADMIN QUEUE: Pending = needs a human. Auto-approved = read-only history.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_list_deposit_requests(
    p_status TEXT    DEFAULT NULL,
    p_limit  INTEGER DEFAULT 200
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_out    JSONB;
    v_filter TEXT := upper(COALESCE(p_status, ''));
BEGIN
    PERFORM public.fx_require_admin();

    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.sort_key DESC), '[]'::JSONB)
      INTO v_out
    FROM (
        SELECT to_jsonb(d) || jsonb_build_object('user_email', u.email) AS j,
               COALESCE(CASE WHEN v_filter = 'AUTO_APPROVED' THEN d.reviewed_at END, d.created_at) AS sort_key
        FROM public.deposit_requests d
        LEFT JOIN auth.users u ON u.id::TEXT = d.user_id
        WHERE CASE v_filter
                -- Needs human action: manual claims with proof, legacy claims,
                -- and automatic ones that failed / timed out / were above the limit.
                WHEN 'PENDING' THEN d.status = 'PENDING'
                    AND (d.verification_status = 'FAILED'
                         OR (d.verification_status = 'NOT_REQUIRED'
                             AND (d.proof_path IS NOT NULL OR d.txid IS NOT NULL)))
                WHEN 'AUTO_APPROVED' THEN d.approved_by_system
                WHEN '' THEN TRUE
                ELSE d.status = v_filter
              END
        ORDER BY sort_key DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
    ) x;

    RETURN v_out;
END;
$$;

-- ------------------------------------------------------------------------------
-- 9. ADMIN REVIEW: unchanged behaviour, but never while the system is verifying
--    (prevents an admin and the verifier both handling the same deposit).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_review_deposit(
    p_deposit_id      UUID,
    p_approve         BOOLEAN,
    p_amount_credited NUMERIC DEFAULT NULL,
    p_reason          TEXT    DEFAULT NULL,
    p_admin_note      TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin  TEXT;
    v_caller TEXT;
    v_d      public.deposit_requests;
    v_wallet public.wallets;
    v_new    NUMERIC;
BEGIN
    v_admin  := public.fx_require_admin();
    v_caller := public.fx_auth_user_id();

    IF p_approve IS NULL THEN
        RAISE EXCEPTION 'BAD_DECISION: p_approve must be true or false' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_d FROM public.deposit_requests WHERE id = p_deposit_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no deposit request %', p_deposit_id USING ERRCODE = '22023';
    END IF;

    IF v_caller IS NOT NULL AND v_caller = v_d.user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: an administrator cannot review their own deposit'
            USING ERRCODE = '42501';
    END IF;

    IF v_d.status <> 'PENDING' THEN
        SELECT balance INTO v_new FROM public.wallets WHERE user_id = v_d.user_id AND currency = 'USD';
        RETURN jsonb_build_object('status', 'already_reviewed', 'deposit', to_jsonb(v_d), 'new_balance', v_new,
                                  'message', format('This deposit was already %s.', lower(v_d.status)));
    END IF;

    IF v_d.verification_status = 'WAITING' THEN
        RAISE EXCEPTION 'AUTO_VERIFY_IN_PROGRESS: the system is still verifying this deposit on the blockchain'
            USING ERRCODE = '22023';
    END IF;

    IF p_approve THEN
        IF p_amount_credited IS NULL OR p_amount_credited <= 0 THEN
            RAISE EXCEPTION 'BAD_AMOUNT: enter the amount actually received on-chain (greater than zero)'
                USING ERRCODE = '22023';
        END IF;
        IF p_amount_credited >= 100000000000000 THEN
            RAISE EXCEPTION 'BAD_AMOUNT: credited amount is out of range' USING ERRCODE = '22023';
        END IF;

        v_wallet := public.fx_lock_wallet(v_d.user_id);
        v_new    := v_wallet.balance + ROUND(p_amount_credited, 4);

        UPDATE public.wallets SET balance = v_new, updated_at = NOW()
         WHERE user_id = v_d.user_id AND currency = 'USD';

        UPDATE public.deposit_requests
           SET status = 'APPROVED', amount_credited = ROUND(p_amount_credited, 4),
               reviewed_by = v_admin, reviewed_at = NOW(),
               admin_note = NULLIF(btrim(COALESCE(p_admin_note, '')), ''), updated_at = NOW()
         WHERE id = p_deposit_id
        RETURNING * INTO v_d;

        PERFORM public.fx_post_ledger(
            v_d.user_id, 'deposit', v_d.amount_credited, v_new, v_d.id::TEXT,
            format('USDT %s deposit approved by %s (txid %s)', v_d.network, v_admin, COALESCE(v_d.txid, 'n/a')),
            'deposit:' || v_d.id::TEXT);

        RETURN jsonb_build_object('status', 'success', 'deposit', to_jsonb(v_d), 'new_balance', v_new);
    END IF;

    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'REASON_REQUIRED: a written reason is required to reject a deposit' USING ERRCODE = '22023';
    END IF;

    UPDATE public.deposit_requests
       SET status = 'REJECTED', reject_reason = btrim(p_reason), reviewed_by = v_admin, reviewed_at = NOW(),
           admin_note = NULLIF(btrim(COALESCE(p_admin_note, '')), ''), updated_at = NOW()
     WHERE id = p_deposit_id
    RETURNING * INTO v_d;

    SELECT balance INTO v_new FROM public.wallets WHERE user_id = v_d.user_id AND currency = 'USD';
    RETURN jsonb_build_object('status', 'success', 'deposit', to_jsonb(v_d), 'new_balance', v_new);
END;
$$;

-- ------------------------------------------------------------------------------
-- 10. ADMIN: MANAGE COMPANY ADDRESSES (audited)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_list_deposit_addresses()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.fx_require_admin();
    RETURN (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.sort_order, a.created_at), '[]'::JSONB)
            FROM public.company_deposit_addresses a);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_admin_upsert_deposit_address(
    p_address              TEXT,
    p_label                TEXT    DEFAULT NULL,
    p_weight               INTEGER DEFAULT NULL,
    p_is_active            BOOLEAN DEFAULT NULL,
    p_auto_verify          BOOLEAN DEFAULT NULL,
    p_max_auto_approve_usd NUMERIC DEFAULT NULL,
    p_sort_order           INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_addr  TEXT;
    v_old   public.company_deposit_addresses;
    v_new   public.company_deposit_addresses;
BEGIN
    v_admin := public.fx_require_admin();
    v_addr  := btrim(COALESCE(p_address, ''));
    IF v_addr !~ '^T[1-9A-HJ-NP-Za-km-z]{33}$' THEN
        RAISE EXCEPTION 'BAD_ADDRESS: enter a valid TRC-20 address (starts with T, 34 characters)' USING ERRCODE = '22023';
    END IF;
    IF p_weight IS NOT NULL AND (p_weight < 0 OR p_weight > 100) THEN
        RAISE EXCEPTION 'BAD_WEIGHT: weight must be between 0 and 100' USING ERRCODE = '22023';
    END IF;
    IF p_max_auto_approve_usd IS NOT NULL AND p_max_auto_approve_usd < 0 THEN
        RAISE EXCEPTION 'BAD_LIMIT: the automatic approval limit cannot be negative' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_old FROM public.company_deposit_addresses WHERE address = v_addr FOR UPDATE;

    INSERT INTO public.company_deposit_addresses
        (address, label, weight, is_active, auto_verify, max_auto_approve_usd, sort_order)
    VALUES (v_addr, NULLIF(btrim(COALESCE(p_label, '')), ''), COALESCE(p_weight, 1), COALESCE(p_is_active, TRUE),
            COALESCE(p_auto_verify, FALSE), COALESCE(p_max_auto_approve_usd, 1000),
            COALESCE(p_sort_order, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM public.company_deposit_addresses)))
    ON CONFLICT (address) DO UPDATE
        SET label                = COALESCE(NULLIF(btrim(COALESCE(p_label, '')), ''), company_deposit_addresses.label),
            weight               = COALESCE(p_weight, company_deposit_addresses.weight),
            is_active            = COALESCE(p_is_active, company_deposit_addresses.is_active),
            auto_verify          = COALESCE(p_auto_verify, company_deposit_addresses.auto_verify),
            max_auto_approve_usd = COALESCE(p_max_auto_approve_usd, company_deposit_addresses.max_auto_approve_usd),
            sort_order           = COALESCE(p_sort_order, company_deposit_addresses.sort_order),
            updated_at           = NOW()
    RETURNING * INTO v_new;

    IF NOT EXISTS (SELECT 1 FROM public.company_deposit_addresses WHERE is_active AND weight > 0) THEN
        RAISE EXCEPTION 'NO_ACTIVE_ADDRESS: at least one active address with weight > 0 is required' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
    VALUES (v_admin, 'upsert_deposit_address', v_addr,
            CASE WHEN v_old.address IS NULL THEN NULL ELSE to_jsonb(v_old) END, to_jsonb(v_new));

    RETURN jsonb_build_object('status', 'success', 'address', to_jsonb(v_new));
END;
$$;

-- ------------------------------------------------------------------------------
-- 11. GRANTS
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_attach_deposit_proof(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_create_deposit_request(NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_attach_deposit_proof(UUID, TEXT) TO authenticated;

-- System RPCs: backend only (fx_is_backend is re-checked inside as well).
REVOKE ALL ON FUNCTION public.rpc_system_approve_deposit(UUID, TEXT, NUMERIC, TEXT, TEXT, BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_system_mark_verification(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_system_approve_deposit(UUID, TEXT, NUMERIC, TEXT, TEXT, BIGINT) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_system_mark_verification(UUID, TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_admin_list_deposit_requests(TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_review_deposit(UUID, BOOLEAN, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_list_deposit_addresses() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_upsert_deposit_address(TEXT, TEXT, INTEGER, BOOLEAN, BOOLEAN, NUMERIC, INTEGER) FROM PUBLIC, anon;
-- Admin-gated inside (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_list_deposit_requests(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_review_deposit(UUID, BOOLEAN, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_list_deposit_addresses() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_upsert_deposit_address(TEXT, TEXT, INTEGER, BOOLEAN, BOOLEAN, NUMERIC, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';


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
