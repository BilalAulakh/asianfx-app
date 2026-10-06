-- ==============================================================================
-- MIGRATION: 20261002000000_manual_deposits.sql
--
-- Replaces the Tatum auto-verification pipeline with MANUAL deposit approval.
--
--   user   -> rpc_submit_deposit_request  (claim: amount + TXID + optional proof)
--   admin  -> checks the TXID on Tronscan by hand
--   admin  -> rpc_review_deposit          (approve with the amount actually seen
--                                          on-chain, or reject with a reason)
--
-- Additive and idempotent. The legacy `deposits` table and
-- `credit_verified_deposit()` are kept for their historical rows; the function
-- is simply no longer reachable by any client role.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. RETIRE THE TATUM CREDIT PATH
--    Every overload, whatever its exact signature on this project.
-- ------------------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'credit_verified_deposit'
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
    END LOOP;
END $$;

-- Historical deposits stay readable by their owner; nobody writes them from a client.
DO $$
BEGIN
    IF to_regclass('public.deposits') IS NOT NULL THEN
        REVOKE INSERT, UPDATE, DELETE ON public.deposits FROM anon, authenticated;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 1. BROKER CONFIG: the company address lives in the DATABASE, not in the app
-- ------------------------------------------------------------------------------
ALTER TABLE public.broker_config ADD COLUMN IF NOT EXISTS deposit_address_trc20 TEXT;
ALTER TABLE public.broker_config ADD COLUMN IF NOT EXISTS min_deposit_usd NUMERIC(18, 4) NOT NULL DEFAULT 10;

-- A mistyped address would send customer funds into the void: only accept a
-- syntactically valid base58 TRON address (T + 33 chars).
ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_deposit_address_trc20_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_deposit_address_trc20_check
    CHECK (deposit_address_trc20 IS NULL
           OR deposit_address_trc20 ~ '^T[1-9A-HJ-NP-Za-km-z]{33}$');

ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_min_deposit_usd_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_min_deposit_usd_check
    CHECK (min_deposit_usd > 0);

-- ------------------------------------------------------------------------------
-- 2. DEPOSIT REQUESTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposit_requests (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          TEXT           NOT NULL,
    amount_claimed   NUMERIC(18, 4) NOT NULL CHECK (amount_claimed > 0),
    network          TEXT           NOT NULL DEFAULT 'TRC20',
    token            TEXT           NOT NULL DEFAULT 'USDT',
    txid             TEXT           NOT NULL,
    from_address     TEXT,
    -- Address the user was shown at submit time (audit: which wallet to check).
    deposit_address  TEXT,
    -- Storage object path inside the private 'deposit-proofs' bucket.
    proof_path       TEXT,
    status           TEXT           NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    amount_credited  NUMERIC(18, 4) CHECK (amount_credited IS NULL OR amount_credited > 0),
    reviewed_by      TEXT,
    reviewed_at      TIMESTAMPTZ,
    reject_reason    TEXT,
    admin_note       TEXT,
    -- Client idempotency key (one submit tap -> at most one row).
    request_id       TEXT,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

ALTER TABLE public.deposit_requests DROP CONSTRAINT IF EXISTS deposit_requests_txid_format;
ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_txid_format
    CHECK (txid ~ '^[0-9a-f]{64}$');

-- A reviewed row must carry its verdict.
ALTER TABLE public.deposit_requests DROP CONSTRAINT IF EXISTS deposit_requests_verdict_shape;
ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_verdict_shape
    CHECK (
        (status = 'PENDING'  AND amount_credited IS NULL AND reviewed_at IS NULL)
     OR (status = 'APPROVED' AND amount_credited IS NOT NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
     OR (status = 'REJECTED' AND amount_credited IS NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
                              AND COALESCE(btrim(reject_reason), '') <> '')
    );

-- One TXID can be claimed exactly once, across ALL rows (rejected ones too).
CREATE UNIQUE INDEX IF NOT EXISTS uq_deposit_requests_txid
    ON public.deposit_requests (lower(txid));

CREATE UNIQUE INDEX IF NOT EXISTS uq_deposit_requests_request
    ON public.deposit_requests (user_id, request_id) WHERE request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_deposit_requests_user
    ON public.deposit_requests (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deposit_requests_pending
    ON public.deposit_requests (created_at) WHERE status = 'PENDING';

-- ------------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY — read-only for clients, writes only through the RPCs
-- ------------------------------------------------------------------------------
ALTER TABLE public.deposit_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deposit_requests_select_own" ON public.deposit_requests;
CREATE POLICY "deposit_requests_select_own" ON public.deposit_requests
    FOR SELECT TO authenticated
    USING (auth.uid()::TEXT = user_id);

DROP POLICY IF EXISTS "deposit_requests_select_admin" ON public.deposit_requests;
CREATE POLICY "deposit_requests_select_admin" ON public.deposit_requests
    FOR SELECT TO authenticated
    USING (public.fx_is_admin());

REVOKE ALL ON public.deposit_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.deposit_requests FROM authenticated;

-- Column-level read grant: the internal review fields (admin_note, reviewed_by)
-- are never exposed to the depositor. Admins read everything through
-- rpc_admin_list_deposit_requests below.
REVOKE SELECT ON public.deposit_requests FROM authenticated;
GRANT SELECT (id, user_id, amount_claimed, network, token, txid, from_address,
              deposit_address, proof_path, status, amount_credited, reviewed_at,
              reject_reason, created_at, updated_at)
    ON public.deposit_requests TO authenticated;

-- ------------------------------------------------------------------------------
-- 4. HELPERS
-- ------------------------------------------------------------------------------

-- Depositor-safe projection of a request row.
CREATE OR REPLACE FUNCTION public.fx_deposit_public_json(p public.deposit_requests)
RETURNS JSONB
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$ SELECT to_jsonb(p) - 'admin_note' - 'reviewed_by' - 'request_id' $$;

REVOKE ALL ON FUNCTION public.fx_deposit_public_json(public.deposit_requests) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------------------
-- 5. SUBMIT A DEPOSIT CLAIM (authenticated user)
--    Never touches the wallet: money only moves in rpc_review_deposit.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_submit_deposit_request(
    p_amount       NUMERIC,
    p_txid         TEXT,
    p_from_address TEXT DEFAULT NULL,
    p_proof_path   TEXT DEFAULT NULL,
    p_request_id   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid        TEXT;
    v_cfg        public.broker_config;
    v_txid       TEXT;
    v_from       TEXT;
    v_proof      TEXT;
    v_pending    INTEGER;
    v_row        public.deposit_requests;
    v_constraint TEXT;
BEGIN
    v_uid := public.fx_require_user_id();

    -- ---- Idempotency: a retried submit returns the row it already created.
    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_row FROM public.deposit_requests
        WHERE user_id = v_uid AND request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate',
                                      'deposit', public.fx_deposit_public_json(v_row));
        END IF;
    END IF;

    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    IF v_cfg.deposit_address_trc20 IS NULL THEN
        RAISE EXCEPTION 'DEPOSITS_DISABLED: deposits are not configured yet. Please contact support.'
            USING ERRCODE = '22023';
    END IF;

    -- ---- TXID: a TRON transaction hash is exactly 64 hex characters.
    v_txid := lower(btrim(COALESCE(p_txid, '')));
    IF v_txid !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'BAD_TXID: a TRON transaction ID must be 64 hexadecimal characters'
            USING ERRCODE = '22023';
    END IF;

    -- ---- Amount
    IF p_amount IS NULL OR p_amount < v_cfg.min_deposit_usd THEN
        RAISE EXCEPTION 'AMOUNT_TOO_SMALL: the minimum deposit is % USD', v_cfg.min_deposit_usd
            USING ERRCODE = '22023';
    END IF;
    IF p_amount >= 100000000000000 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: deposit amount is out of range' USING ERRCODE = '22023';
    END IF;

    -- ---- Optional sender address
    v_from := NULLIF(btrim(COALESCE(p_from_address, '')), '');
    IF v_from IS NOT NULL AND v_from !~ '^T[1-9A-HJ-NP-Za-km-z]{33}$' THEN
        RAISE EXCEPTION 'BAD_ADDRESS: the sender address is not a valid TRON (TRC-20) address'
            USING ERRCODE = '22023';
    END IF;

    -- ---- Optional proof: must be an object inside the caller's own folder.
    v_proof := NULLIF(btrim(COALESCE(p_proof_path, '')), '');
    IF v_proof IS NOT NULL THEN
        IF left(v_proof, length(v_uid) + 1) <> v_uid || '/'
           OR position('..' IN v_proof) > 0
           OR length(v_proof) > 512
        THEN
            RAISE EXCEPTION 'BAD_PROOF_PATH: the payment proof must be uploaded to your own folder'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Serialise submissions per user so the pending cap below is race-free.
    PERFORM pg_advisory_xact_lock(hashtext('fx_deposit_request:' || v_uid));

    -- ---- A TXID can never be claimed twice — not even after a rejection —
    --      and never if the legacy Tatum pipeline already credited it.
    IF EXISTS (SELECT 1 FROM public.deposit_requests WHERE lower(txid) = v_txid) THEN
        RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been submitted'
            USING ERRCODE = '23505';
    END IF;
    IF to_regclass('public.deposits') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.deposits WHERE lower(txid) = v_txid) THEN
            RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been credited'
                USING ERRCODE = '23505';
        END IF;
    END IF;

    -- ---- Anti-spam
    SELECT COUNT(*) INTO v_pending FROM public.deposit_requests
    WHERE user_id = v_uid AND status = 'PENDING';
    IF v_pending >= 5 THEN
        RAISE EXCEPTION 'TOO_MANY_PENDING: you already have % deposits awaiting review', v_pending
            USING ERRCODE = '22023';
    END IF;

    BEGIN
        INSERT INTO public.deposit_requests
            (user_id, amount_claimed, txid, from_address, deposit_address, proof_path, request_id)
        VALUES
            (v_uid, ROUND(p_amount, 4), v_txid, v_from, v_cfg.deposit_address_trc20, v_proof, p_request_id)
        RETURNING * INTO v_row;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'uq_deposit_requests_request' THEN
            SELECT * INTO v_row FROM public.deposit_requests
            WHERE user_id = v_uid AND request_id = p_request_id;
            RETURN jsonb_build_object('status', 'duplicate',
                                      'deposit', public.fx_deposit_public_json(v_row));
        END IF;
        RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been submitted'
            USING ERRCODE = '23505';
    END;

    RETURN jsonb_build_object('status', 'success',
                              'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. REVIEW A DEPOSIT (administrator only)
--
-- Lock order: the request row, then the wallet (via fx_lock_wallet). No other
-- code path locks a wallet and then a deposit request, so this cannot deadlock
-- against trading.
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
        RAISE EXCEPTION 'DEPOSIT_NOT_FOUND: no deposit request %', p_deposit_id
            USING ERRCODE = '22023';
    END IF;

    -- Four-eyes rule: nobody reviews money flowing into their own account.
    IF v_caller IS NOT NULL AND v_caller = v_d.user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: an administrator cannot review their own deposit'
            USING ERRCODE = '42501';
    END IF;

    -- Only PENDING can be reviewed. A second click / second admin gets the
    -- existing verdict back and nothing moves.
    IF v_d.status <> 'PENDING' THEN
        SELECT balance INTO v_new FROM public.wallets
        WHERE user_id = v_d.user_id AND currency = 'USD';
        RETURN jsonb_build_object(
            'status', 'already_reviewed',
            'deposit', to_jsonb(v_d),
            'new_balance', v_new,
            'message', format('This deposit was already %s.', lower(v_d.status)));
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

        UPDATE public.wallets
           SET balance = v_new, updated_at = NOW()
         WHERE user_id = v_d.user_id AND currency = 'USD';

        UPDATE public.deposit_requests
           SET status          = 'APPROVED',
               amount_credited = ROUND(p_amount_credited, 4),
               reviewed_by     = v_admin,
               reviewed_at     = NOW(),
               admin_note      = NULLIF(btrim(COALESCE(p_admin_note, '')), ''),
               updated_at      = NOW()
         WHERE id = p_deposit_id
        RETURNING * INTO v_d;

        PERFORM public.fx_post_ledger(
            v_d.user_id, 'deposit', v_d.amount_credited, v_new, v_d.id::TEXT,
            format('USDT %s deposit approved by %s (txid %s)', v_d.network, v_admin, v_d.txid),
            'deposit:' || v_d.id::TEXT);

        RETURN jsonb_build_object('status', 'success', 'deposit', to_jsonb(v_d), 'new_balance', v_new);
    END IF;

    -- ---- Reject: a reason is mandatory, the wallet is untouched.
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'REASON_REQUIRED: a written reason is required to reject a deposit'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.deposit_requests
       SET status        = 'REJECTED',
           reject_reason = btrim(p_reason),
           reviewed_by   = v_admin,
           reviewed_at   = NOW(),
           admin_note    = NULLIF(btrim(COALESCE(p_admin_note, '')), ''),
           updated_at    = NOW()
     WHERE id = p_deposit_id
    RETURNING * INTO v_d;

    SELECT balance INTO v_new FROM public.wallets
    WHERE user_id = v_d.user_id AND currency = 'USD';

    RETURN jsonb_build_object('status', 'success', 'deposit', to_jsonb(v_d), 'new_balance', v_new);
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. ADMIN QUEUE (with the depositor's e-mail, which clients cannot read)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_list_deposit_requests(
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
        SELECT to_jsonb(d) || jsonb_build_object('user_email', u.email) AS j,
               (d.status = 'PENDING') AS is_pending,
               d.created_at
        FROM public.deposit_requests d
        LEFT JOIN auth.users u ON u.id::TEXT = d.user_id
        WHERE p_status IS NULL OR d.status = upper(p_status)
        ORDER BY (d.status = 'PENDING') DESC, d.created_at DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 500)
    ) x;

    RETURN v_out;
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. PRIVATE PROOF STORAGE — same pattern as 'kyc-documents'
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('deposit-proofs', 'deposit-proofs', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Size / type limits, where the storage schema supports them.
DO $$
BEGIN
    UPDATE storage.buckets
       SET public = FALSE,
           file_size_limit = 10485760,
           allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp']
     WHERE id = 'deposit-proofs';
EXCEPTION WHEN undefined_column THEN
    UPDATE storage.buckets SET public = FALSE WHERE id = 'deposit-proofs';
END $$;

DROP POLICY IF EXISTS "deposit_proofs_insert_own" ON storage.objects;
CREATE POLICY "deposit_proofs_insert_own" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'deposit-proofs'
        AND (storage.foldername(name))[1] = auth.uid()::TEXT
    );

DROP POLICY IF EXISTS "deposit_proofs_select_own_or_admin" ON storage.objects;
CREATE POLICY "deposit_proofs_select_own_or_admin" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'deposit-proofs'
        AND ((storage.foldername(name))[1] = auth.uid()::TEXT OR public.fx_is_admin())
    );
-- No UPDATE / DELETE policy: a submitted proof cannot be swapped afterwards.

-- ------------------------------------------------------------------------------
-- 9. GRANTS
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rpc_submit_deposit_request(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_review_deposit(UUID, BOOLEAN, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_list_deposit_requests(TEXT, INTEGER) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.rpc_submit_deposit_request(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
-- Admin-gated inside the function (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_review_deposit(UUID, BOOLEAN, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_list_deposit_requests(TEXT, INTEGER) TO authenticated;
