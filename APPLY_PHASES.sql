-- ##############################################################################
--  APPLY_PHASES.sql  —  GENERATED from supabase/migrations, DO NOT EDIT
--
--  Paste into the Supabase SQL Editor and Run. Idempotent; safe to repeat.
--    1. 20261002000000_manual_deposits.sql
--    2. 20261002000100_admin_privilege_fix.sql
--    3. 20261002000200_server_quotes_only.sql
--    4. 20261002000300_dealer_controls.sql
--    5. 20261002000400_engine_correctness.sql
--  Afterwards:  UPDATE public.broker_config SET deposit_address_trc20 = 'T...' WHERE id = 1;
-- ##############################################################################


-- ==== BEGIN 202610020000a00_manual_deposits.sql ====

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

-- ==== END 20261002000000_manual_deposits.sql ====


-- ==== BEGIN 20261002000100_admin_privilege_fix.sql ====

-- ==============================================================================
-- MIGRATION: 20261002000100_admin_privilege_fix.sql
--
-- PRIVILEGE ESCALATION FIX.
--
-- fx_is_admin() accepted `auth.jwt() -> 'user_metadata' ->> 'role'`. user_metadata
-- is written BY THE USER (supabase.auth.signUp({data}) / auth.updateUser({data})),
-- so any account could make itself an administrator:
--     await supabase.auth.updateUser(UserAttributes(data: {'role': 'admin'}));
-- ...and then approve its own KYC, read every wallet, adjust balances, etc.
--
-- An administrator is now ONLY:
--   * the service_role key (backend / Edge Functions), or
--   * a user whose app_metadata.role is admin/superadmin (app_metadata can only
--     be written with the service key), or
--   * a user listed in public.broker_admins.
--
-- ------------------------------------------------------------------------------
-- AUDIT — run these BEFORE and AFTER applying, and investigate every hit:
--
--   -- accounts that tried to self-promote through user_metadata
--   select id, email, created_at, last_sign_in_at
--   from auth.users
--   where raw_user_meta_data->>'role' in ('admin','superadmin');
--
--   -- who is an admin under the NEW rule
--   select b.user_id, u.email, b.note, b.added_by, b.created_at
--   from public.broker_admins b left join auth.users u on u.id::text = b.user_id;
--   select id, email from auth.users
--   where raw_app_meta_data->>'role' in ('admin','superadmin');
--
--   -- money moved by anyone who held admin through user_metadata
--   select a.* from public.admin_balance_adjustments a
--   join auth.users u on u.id::text = a.admin_id
--   where u.raw_user_meta_data->>'role' in ('admin','superadmin');
--
-- NOTE: migration 20261001000300 seeded broker_admins from the account with the
-- e-mail admin@asianfx.com. The old app shipped that account's password
-- ('Admin@123') inside the APK and would even auto-create it, so whoever
-- controls that row must be verified and its password rotated (see
-- SECURITY_CHANGES.md). This migration does not delete it, to avoid locking the
-- real operator out.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.fx_is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
        OR COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') IN ('admin', 'superadmin')
        OR EXISTS (
            SELECT 1 FROM public.broker_admins b
            WHERE b.user_id = auth.uid()::TEXT
        );
$$;

-- RLS policies call it, so the client roles must be able to execute it
-- (an anon caller simply gets FALSE).
GRANT EXECUTE ON FUNCTION public.fx_is_admin() TO authenticated, service_role;

-- ------------------------------------------------------------------------------
-- rpc_whoami — the app decides whether to SHOW admin screens from this.
-- (Cosmetic only: every admin RPC re-checks fx_is_admin() itself.)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_whoami()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT jsonb_build_object(
        'user_id',  public.fx_auth_user_id(),
        'is_admin', public.fx_is_admin()
    );
$$;

REVOKE ALL ON FUNCTION public.rpc_whoami() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_whoami() TO authenticated;

-- ==== END 20261002000100_admin_privilege_fix.sql ====


-- ==== BEGIN 20261002000200_server_quotes_only.sql ====

-- ==============================================================================
-- MIGRATION: 20261002000200_server_quotes_only.sql
--
-- CLIENT-SUBMITTED PRICES.
--
-- fx_resolve_quote() let the app hand in its own bid/ask (p_quotes). When no
-- fresh publisher quote existed it accepted any client price within 2% of the
-- LAST STORED price — and then persisted it as the new reference. A client
-- could therefore walk the reference 2% per call, fill at a price of its
-- choosing, and supply its own quote->USD conversion `rate` as well.
--
-- New rules:
--   * Execution prices come ONLY from a fresh `publisher` quote (written by the
--     fx-price-sweep Edge Function with the service key).
--   * A client quote is never persisted and never used as a fill price. If
--     client quotes are ever re-enabled, the client's view is only band-checked
--     against the fresh publisher price (a stale-screen guard) and its `rate`
--     is ignored; with no fresh publisher price it is rejected outright.
--   * Strict callers (rpc_open_trade, rpc_close_trade) fail with NO_QUOTE when
--     there is no fresh publisher price (feed down or market closed).
--   * Non-strict callers (account snapshots, the risk sweep) may still SEE the
--     last stored price, labelled source='stale'. The engine no longer EXECUTES
--     on stale prices (see 20261002000400_engine_correctness.sql).
-- ==============================================================================

UPDATE public.broker_config
   SET allow_client_quotes = FALSE,
       quote_band_fraction = 0.003,
       updated_at          = NOW()
 WHERE id = 1;

ALTER TABLE public.broker_config ALTER COLUMN allow_client_quotes SET DEFAULT FALSE;
ALTER TABLE public.broker_config ALTER COLUMN quote_band_fraction SET DEFAULT 0.003;

-- Same signature as before so every existing caller keeps compiling.
-- p_persist is accepted for compatibility and ignored: nothing a client sends
-- is ever written to market_quotes.
CREATE OR REPLACE FUNCTION public.fx_resolve_quote(
    p_symbol  TEXT,
    p_quotes  JSONB   DEFAULT NULL,
    p_persist BOOLEAN DEFAULT TRUE,
    p_strict  BOOLEAN DEFAULT TRUE
)
RETURNS public.fx_quote_t
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_cfg   public.broker_config;
    v_mq    public.market_quotes;
    v_fresh BOOLEAN;
    v_in    JSONB;
    v_bid   NUMERIC;
    v_ask   NUMERIC;
    v_ref   NUMERIC;
    v_out   public.fx_quote_t;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    SELECT * INTO v_mq  FROM public.market_quotes WHERE symbol = p_symbol;

    v_fresh := v_mq.symbol IS NOT NULL
           AND v_mq.source = 'publisher'
           AND v_mq.updated_at > NOW() - make_interval(secs => v_cfg.quote_max_age_seconds);

    -- ---- Optional client quote: a stale-screen guard, never a price source.
    IF v_cfg.allow_client_quotes AND p_quotes IS NOT NULL THEN
        v_in := p_quotes -> p_symbol;
    END IF;

    IF v_in IS NOT NULL AND jsonb_typeof(v_in) = 'object' THEN
        IF NOT v_fresh THEN
            IF p_strict THEN
                RAISE EXCEPTION 'NO_QUOTE: no live server price for % (market closed or price feed offline); client prices are not accepted without one', p_symbol
                    USING ERRCODE = '22023';
            END IF;
            -- Non-strict: ignore the client quote entirely.
        ELSE
            BEGIN
                v_bid := (v_in ->> 'bid')::NUMERIC;
                v_ask := (v_in ->> 'ask')::NUMERIC;
            EXCEPTION WHEN OTHERS THEN
                v_bid := NULL;
                v_ask := NULL;
            END;

            IF v_bid IS NULL OR v_ask IS NULL OR v_bid <= 0 OR v_ask < v_bid THEN
                IF p_strict THEN
                    RAISE EXCEPTION 'BAD_QUOTE: % submitted an invalid bid/ask', p_symbol
                        USING ERRCODE = '22023';
                END IF;
            ELSE
                v_ref := (v_mq.bid + v_mq.ask) / 2;
                IF v_ref > 0
                   AND ABS(((v_bid + v_ask) / 2) - v_ref) / v_ref > v_cfg.quote_band_fraction
                   AND p_strict
                THEN
                    RAISE EXCEPTION
                        'QUOTE_OUT_OF_BAND: the price on screen for % (mid %) is more than % pct away from the live price (mid %); refresh and try again',
                        p_symbol, ROUND((v_bid + v_ask) / 2, 8), (v_cfg.quote_band_fraction * 100), ROUND(v_ref, 8)
                        USING ERRCODE = '22023';
                END IF;
            END IF;
            -- 'rate' from the client is ignored by construction: the fill below
            -- always carries the publisher's own conversion rate.
        END IF;
    END IF;

    -- ---- 1. Fresh publisher quote: the only execution price.
    IF v_fresh THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'publisher', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    -- ---- 2. No fresh price.
    IF p_strict THEN
        RAISE EXCEPTION 'NO_QUOTE: no live price for % right now (market closed or price feed offline)', p_symbol
            USING ERRCODE = '22023';
    END IF;

    IF v_mq.symbol IS NOT NULL THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'stale', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    v_out := ROW(p_symbol, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC, 'none', NULL::TIMESTAMPTZ)::public.fx_quote_t;
    RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.fx_resolve_quote(TEXT, JSONB, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- rpc_sync_account used to pre-persist client quotes before evaluating. That
-- step is gone; p_quotes is accepted for compatibility and ignored.
CREATE OR REPLACE FUNCTION public.rpc_sync_account(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    RETURN public.fx_evaluate_account(v_uid, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_sync_account(JSONB) TO authenticated;

-- rpc_get_account_state: likewise ignore client quotes for the snapshot.
CREATE OR REPLACE FUNCTION public.rpc_get_account_state(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    RETURN public.fx_account_snapshot(v_uid, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_account_state(JSONB) TO authenticated;

-- ==== END 20261002000200_server_quotes_only.sql ====


-- ==== BEGIN 20261002000300_dealer_controls.sql ====

-- ==============================================================================
-- MIGRATION: 20261002000300_dealer_controls.sql
--
-- Dealer controls that used to live only in the admin's phone memory
-- (MarketFeedService._spreadMarkupMap / AdminCubit.spreadMultiplier) are now
-- persisted, audited, and actually applied by the price publisher.
--
--   instruments.spread_markup_points  <- rpc_admin_set_markup (0..500, audited)
--   broker_config.spread_multiplier   <- rpc_admin_set_spread_multiplier (1..10)
--
-- fx-price-sweep publishes bid/ask with
--   spread = round(spread_markup_points * spread_multiplier) * point_size
-- ==============================================================================

ALTER TABLE public.broker_config
    ADD COLUMN IF NOT EXISTS spread_multiplier NUMERIC(6, 3) NOT NULL DEFAULT 1.000;

ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_spread_multiplier_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_spread_multiplier_check
    CHECK (spread_multiplier >= 1 AND spread_multiplier <= 10);

ALTER TABLE public.instruments DROP CONSTRAINT IF EXISTS instruments_spread_markup_points_check;
ALTER TABLE public.instruments ADD CONSTRAINT instruments_spread_markup_points_check
    CHECK (spread_markup_points >= 0 AND spread_markup_points <= 500);

-- ------------------------------------------------------------------------------
-- Append-only audit trail for dealer / broker configuration changes.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_config_audit (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id    TEXT        NOT NULL,
    action      TEXT        NOT NULL,
    target      TEXT,
    old_value   JSONB,
    new_value   JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_config_audit_created ON public.admin_config_audit (created_at DESC);

ALTER TABLE public.admin_config_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_config_audit_select_admin" ON public.admin_config_audit;
CREATE POLICY "admin_config_audit_select_admin" ON public.admin_config_audit
    FOR SELECT TO authenticated
    USING (public.fx_is_admin());

REVOKE ALL ON public.admin_config_audit FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.admin_config_audit FROM authenticated;

-- ------------------------------------------------------------------------------
-- Per-instrument dealer markup
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_set_markup(p_symbol TEXT, p_points INTEGER)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_old   INTEGER;
    v_new   INTEGER;
BEGIN
    v_admin := public.fx_require_admin();

    IF p_points IS NULL THEN
        RAISE EXCEPTION 'BAD_MARKUP: markup points are required' USING ERRCODE = '22023';
    END IF;
    v_new := LEAST(GREATEST(p_points, 0), 500);

    SELECT spread_markup_points INTO v_old
    FROM public.instruments WHERE symbol = p_symbol FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UNKNOWN_INSTRUMENT: % is not offered by this broker', p_symbol
            USING ERRCODE = '22023';
    END IF;

    IF v_old IS DISTINCT FROM v_new THEN
        UPDATE public.instruments
           SET spread_markup_points = v_new, updated_at = NOW()
         WHERE symbol = p_symbol;

        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_markup', p_symbol,
                jsonb_build_object('spread_markup_points', v_old),
                jsonb_build_object('spread_markup_points', v_new, 'requested', p_points));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'symbol', p_symbol,
                              'spread_markup_points', v_new, 'previous', v_old);
END;
$$;

-- ------------------------------------------------------------------------------
-- Global spread multiplier (news / volatility widening)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_set_spread_multiplier(p_multiplier NUMERIC)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_old   NUMERIC;
    v_new   NUMERIC;
BEGIN
    v_admin := public.fx_require_admin();

    IF p_multiplier IS NULL THEN
        RAISE EXCEPTION 'BAD_MULTIPLIER: a multiplier is required' USING ERRCODE = '22023';
    END IF;
    v_new := ROUND(LEAST(GREATEST(p_multiplier, 1), 10), 3);

    SELECT spread_multiplier INTO v_old FROM public.broker_config WHERE id = 1 FOR UPDATE;

    IF v_old IS DISTINCT FROM v_new THEN
        UPDATE public.broker_config SET spread_multiplier = v_new, updated_at = NOW() WHERE id = 1;

        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_spread_multiplier', 'broker_config',
                jsonb_build_object('spread_multiplier', v_old),
                jsonb_build_object('spread_multiplier', v_new, 'requested', p_multiplier));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'spread_multiplier', v_new, 'previous', v_old);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_set_markup(TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_set_spread_multiplier(NUMERIC) FROM PUBLIC, anon;
-- Admin-gated inside the functions (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_markup(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_spread_multiplier(NUMERIC) TO authenticated;

-- ==== END 20261002000300_dealer_controls.sql ====


-- ==== BEGIN 20261002000400_engine_correctness.sql ====

-- ==============================================================================
-- MIGRATION: 20261002000400_engine_correctness.sql
--
-- Engine correctness fixes:
--
--  1. STOP-LOSS GAP FILL. A triggered stop loss was settled AT the stop level
--     even when the market had gapped straight through it (weekend open, news),
--     handing the client a price that never traded. A stop loss is a stop
--     order: once triggered it fills at the current executable price (bid for a
--     long, ask for a short), never better than the stop level. Pending STOP
--     entry orders already filled at the current bid/ask; that is kept.
--     Take profit still fills at its level.
--
--  2. NO EXECUTION ON STALE PRICES. Triggers, SL/TP and stop-out now act only
--     on a fresh `publisher` quote. A symbol whose feed is down / market is
--     closed is left untouched until a live price returns.
--
--  3. FAIR SWEEP. rpc_sweep_accounts took `LIMIT 500` of an unordered DISTINCT,
--     so beyond 500 exposed accounts some could be starved forever. Accounts
--     are now processed least-recently-evaluated first (account_sweep_state).
--
--  4. SWAP. Swap was charged per 24h since open, regardless of the clock, so a
--     position opened 10 minutes before rollover and held over it paid nothing,
--     and weekends were never tripled. It is now charged per ROLLOVER crossed at
--     broker_config.rollover_hour_utc (default 21:00 UTC):
--       forex & metals : Mon-Fri, Wednesday counts x3 (covers the weekend)
--       crypto         : every day x1
--       everything else: Mon-Fri x1
--
--  5. broker_config.require_kyc_for_trading = TRUE.
-- ==============================================================================

ALTER TABLE public.broker_config ADD COLUMN IF NOT EXISTS rollover_hour_utc SMALLINT NOT NULL DEFAULT 21;
ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_rollover_hour_utc_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_rollover_hour_utc_check
    CHECK (rollover_hour_utc BETWEEN 0 AND 23);

UPDATE public.broker_config
   SET require_kyc_for_trading = TRUE,
       updated_at = NOW()
 WHERE id = 1;

ALTER TABLE public.broker_config ALTER COLUMN require_kyc_for_trading SET DEFAULT TRUE;

-- ------------------------------------------------------------------------------
-- Sweep bookkeeping (kept off `wallets` so it does not spam realtime clients).
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_sweep_state (
    user_id           TEXT PRIMARY KEY,
    last_evaluated_at TIMESTAMPTZ,
    last_error        TEXT,
    error_count       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_account_sweep_state_last
    ON public.account_sweep_state (last_evaluated_at NULLS FIRST);

ALTER TABLE public.account_sweep_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_sweep_state FROM anon, authenticated;

-- ------------------------------------------------------------------------------
-- 4. ROLLOVER COUNTING
-- Number of (weighted) rollovers strictly after p_from and up to p_to.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_swap_rollover_count(
    p_from     TIMESTAMPTZ,
    p_to       TIMESTAMPTZ,
    p_category TEXT,
    p_hour     INTEGER DEFAULT 21
)
RETURNS INTEGER
LANGUAGE sql STABLE
SET search_path = public
AS $$
    SELECT COALESCE(SUM(
               CASE
                   WHEN lower(p_category) = 'crypto'                 THEN 1
                   WHEN EXTRACT(ISODOW FROM r) IN (6, 7)             THEN 0
                   WHEN lower(p_category) IN ('forex', 'metals')
                        AND EXTRACT(ISODOW FROM r) = 3               THEN 3
                   ELSE 1
               END), 0)::INTEGER
    FROM generate_series(
             date_trunc('day', p_from AT TIME ZONE 'UTC') + make_interval(hours => GREATEST(LEAST(p_hour, 23), 0)),
             p_to AT TIME ZONE 'UTC',
             INTERVAL '1 day') AS r
    WHERE p_from IS NOT NULL
      AND p_to IS NOT NULL
      AND r >  p_from AT TIME ZONE 'UTC'
      AND r <= p_to   AT TIME ZONE 'UTC';
$$;

-- ------------------------------------------------------------------------------
-- ATOMIC CLOSE PRIMITIVE — identical to 20261001000100 except for the swap.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_close_trade_row(
    p_trade_id     TEXT,
    p_close_price  NUMERIC,
    p_close_bid    NUMERIC,
    p_close_ask    NUMERIC,
    p_rate         NUMERIC,
    p_reason       TEXT,
    p_price_source TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_t        public.trades;
    v_inst     public.instruments;
    v_cfg      public.broker_config;
    v_wallet   public.wallets;
    v_pnl      NUMERIC;
    v_swap     NUMERIC := 0;
    v_rolls    INTEGER := 0;
    v_release  NUMERIC;
    v_new_bal  NUMERIC;
    v_status   TEXT;
BEGIN
    SELECT * INTO v_t FROM public.trades
    WHERE id = p_trade_id AND status = 'open'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'already_closed', 'trade_id', p_trade_id);
    END IF;

    IF p_close_price IS NULL OR p_close_price <= 0 THEN
        RAISE EXCEPTION 'NO_QUOTE: cannot close % without an authoritative price', p_trade_id
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_inst FROM public.instruments WHERE symbol = v_t.symbol;
    SELECT * INTO v_cfg  FROM public.broker_config WHERE id = 1;

    -- Swap: weighted rollovers crossed * lots * per-lot rate for the side.
    IF v_inst.symbol IS NOT NULL THEN
        v_rolls := public.fx_swap_rollover_count(
            COALESCE(v_t.filled_at, v_t.open_time), NOW(), v_inst.category,
            COALESCE(v_cfg.rollover_hour_utc, 21));
        v_swap := ROUND(
            v_rolls * v_t.lots *
            CASE WHEN v_t.side = 'buy' THEN v_inst.swap_long_per_lot ELSE v_inst.swap_short_per_lot END,
            4);
    END IF;

    v_pnl := public.fx_calc_pnl(
        v_t.side, v_t.open_price, p_close_price, v_t.lots, v_t.contract_size,
        COALESCE(p_rate, v_t.quote_to_usd_rate));

    SELECT * INTO v_wallet FROM public.wallets
    WHERE user_id = v_t.user_id AND currency = 'USD' FOR UPDATE;

    v_release := LEAST(COALESCE(v_t.required_margin, 0), COALESCE(v_wallet.held_margin, 0));
    v_new_bal := COALESCE(v_wallet.balance, 0) + v_pnl - v_swap;

    UPDATE public.wallets
       SET held_margin = held_margin - v_release,
           balance     = v_new_bal,
           updated_at  = NOW()
     WHERE user_id = v_t.user_id AND currency = 'USD';

    v_status := CASE WHEN p_reason = 'STOP_OUT' THEN 'liquidated' ELSE 'closed' END;

    UPDATE public.trades
       SET status         = v_status,
           close_price    = p_close_price,
           current_price  = p_close_price,
           close_bid      = p_close_bid,
           close_ask      = p_close_ask,
           realized_pnl   = v_pnl,
           swap           = v_swap,
           unrealized_pnl = 0,
           close_time     = NOW(),
           close_reason   = p_reason,
           price_source   = COALESCE(p_price_source, v_t.price_source),
           updated_at     = NOW()
     WHERE id = p_trade_id;

    PERFORM public.fx_post_ledger(
        v_t.user_id, 'margin_release', v_release, v_new_bal, p_trade_id,
        format('Margin released for %s (%s)', v_t.symbol, p_reason),
        'margin_release:' || p_trade_id);

    IF v_pnl <> 0 THEN
        PERFORM public.fx_post_ledger(
            v_t.user_id,
            CASE WHEN v_pnl > 0 THEN 'realized_profit' ELSE 'realized_loss' END,
            v_pnl, v_new_bal, p_trade_id,
            format('Realized PnL on %s @ %s (%s)', v_t.symbol, p_close_price, p_reason),
            'realized_pnl:' || p_trade_id);
    END IF;

    IF v_swap <> 0 THEN
        PERFORM public.fx_post_ledger(
            v_t.user_id, 'swap', -v_swap, v_new_bal, p_trade_id,
            format('Swap on %s for %s rollover(s)', v_t.symbol, v_rolls),
            'swap:' || p_trade_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'trade_id', p_trade_id,
        'symbol', v_t.symbol,
        'side', v_t.side,
        'lots', v_t.lots,
        'open_price', v_t.open_price,
        'close_price', p_close_price,
        'realized_pnl', v_pnl,
        'swap', v_swap,
        'rollovers', v_rolls,
        'commission', v_t.commission,
        'released_margin', v_release,
        'close_reason', p_reason,
        'trade_status', v_status,
        'new_balance', v_new_bal
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- RISK EVALUATION ENGINE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_evaluate_account(p_user_id TEXT, p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cfg       public.broker_config;
    v_row       RECORD;
    v_q         public.fx_quote_t;
    v_hit       BOOLEAN;
    v_fill      NUMERIC;
    v_reason    TEXT;
    v_res       JSONB;
    v_triggered JSONB := '[]'::JSONB;
    v_closed    JSONB := '[]'::JSONB;
    v_expired   INTEGER := 0;
    v_passes    INTEGER := 0;
    v_snap      JSONB;
    v_level     NUMERIC;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;

    PERFORM public.fx_lock_wallet(p_user_id);

    -- ---- Expire resting orders that outlived their validity.
    UPDATE public.trades
       SET status = 'expired', close_reason = 'EXPIRED', updated_at = NOW()
     WHERE user_id = p_user_id AND status = 'pending'
       AND expires_at IS NOT NULL AND expires_at <= NOW();
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    -- ---- Trigger pending limit / stop orders, on a LIVE price only.
    --      Both fill at the current executable price (a stop through a gap fills
    --      at the post-gap price; a limit fills at its level or better).
    FOR v_row IN
        SELECT id, side, type, target_price, symbol
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'pending'
        ORDER BY created_at
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL OR v_q.source <> 'publisher' OR v_row.target_price IS NULL;

        v_hit := CASE
            WHEN v_row.type = 'limit' AND v_row.side = 'buy'  THEN v_q.ask <= v_row.target_price
            WHEN v_row.type = 'limit' AND v_row.side = 'sell' THEN v_q.bid >= v_row.target_price
            WHEN v_row.type = 'stop'  AND v_row.side = 'buy'  THEN v_q.ask >= v_row.target_price
            WHEN v_row.type = 'stop'  AND v_row.side = 'sell' THEN v_q.bid <= v_row.target_price
            ELSE FALSE
        END;

        IF v_hit THEN
            v_fill := CASE WHEN v_row.side = 'buy' THEN v_q.ask ELSE v_q.bid END;
            v_res  := public.fx_activate_trade(
                v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, v_q.source);
            v_triggered := v_triggered || v_res;
        END IF;
    END LOOP;

    -- ---- Stop loss / take profit on a LIVE price. Risk is checked before reward.
    FOR v_row IN
        SELECT id, side, symbol, stop_loss, take_profit
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'open'
          AND (stop_loss IS NOT NULL OR take_profit IS NOT NULL)
        ORDER BY open_time
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL OR v_q.source <> 'publisher';

        v_reason := NULL;
        IF v_row.side = 'buy' THEN
            IF v_row.stop_loss IS NOT NULL AND v_q.bid <= v_row.stop_loss THEN
                -- Gap fill: the bid, which is at or below the stop.
                v_reason := 'STOP_LOSS'; v_fill := LEAST(v_q.bid, v_row.stop_loss);
            ELSIF v_row.take_profit IS NOT NULL AND v_q.bid >= v_row.take_profit THEN
                v_reason := 'TAKE_PROFIT'; v_fill := v_row.take_profit;
            END IF;
        ELSE
            IF v_row.stop_loss IS NOT NULL AND v_q.ask >= v_row.stop_loss THEN
                -- Gap fill: the ask, which is at or above the stop.
                v_reason := 'STOP_LOSS'; v_fill := GREATEST(v_q.ask, v_row.stop_loss);
            ELSIF v_row.take_profit IS NOT NULL AND v_q.ask <= v_row.take_profit THEN
                v_reason := 'TAKE_PROFIT'; v_fill := v_row.take_profit;
            END IF;
        END IF;

        IF v_reason IS NOT NULL THEN
            v_res := public.fx_close_trade_row(
                v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, v_reason, v_q.source);
            IF (v_res ->> 'status') = 'success' THEN
                v_closed := v_closed || v_res;
            END IF;
        END IF;
    END LOOP;

    -- ---- Stop-out: liquidate the worst LIVE-priced loser, recompute, repeat.
    LOOP
        v_snap  := public.fx_account_snapshot(p_user_id, NULL);
        v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

        EXIT WHEN v_level IS NULL;
        EXIT WHEN v_level > v_cfg.stop_out_level_pct;
        EXIT WHEN (v_snap ->> 'open_positions')::INTEGER = 0;
        EXIT WHEN v_passes >= v_cfg.max_liquidation_passes;

        SELECT t.id, t.side, t.symbol INTO v_row
        FROM public.trades t
        CROSS JOIN LATERAL public.fx_resolve_quote(t.symbol, NULL, FALSE, FALSE) q
        WHERE t.user_id = p_user_id AND t.status = 'open'
          AND q.source = 'publisher'
        ORDER BY public.fx_calc_pnl(
                    t.side, t.open_price,
                    CASE WHEN t.side = 'buy' THEN q.bid ELSE q.ask END,
                    t.lots, t.contract_size, q.quote_to_usd) ASC
        LIMIT 1;
        EXIT WHEN NOT FOUND;

        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        EXIT WHEN v_q.source <> 'publisher';
        v_fill := CASE WHEN v_row.side = 'buy' THEN v_q.bid ELSE v_q.ask END;
        EXIT WHEN v_fill IS NULL;

        v_res := public.fx_close_trade_row(
            v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, 'STOP_OUT', v_q.source);
        EXIT WHEN (v_res ->> 'status') <> 'success';

        v_closed := v_closed || v_res;
        v_passes := v_passes + 1;
    END LOOP;

    v_snap  := public.fx_account_snapshot(p_user_id, NULL);
    v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

    INSERT INTO public.account_sweep_state (user_id, last_evaluated_at, last_error)
    VALUES (p_user_id, NOW(), NULL)
    ON CONFLICT (user_id) DO UPDATE
        SET last_evaluated_at = EXCLUDED.last_evaluated_at, last_error = NULL;

    RETURN jsonb_build_object(
        'status', 'success',
        'triggered', v_triggered,
        'closed', v_closed,
        'expired', v_expired,
        'liquidations', v_passes,
        'margin_call', COALESCE(v_level < v_cfg.margin_call_level_pct, FALSE),
        'stop_out', COALESCE(v_level <= v_cfg.stop_out_level_pct, FALSE),
        'account', v_snap);
END;
$$;

-- ------------------------------------------------------------------------------
-- FAIR OFFLINE SWEEP — least recently evaluated accounts first.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_sweep_accounts(p_max_accounts INTEGER DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid       TEXT;
    v_res       JSONB;
    v_exposed   INTEGER := 0;
    v_accounts  INTEGER := 0;
    v_closed    INTEGER := 0;
    v_triggered INTEGER := 0;
    v_errors    INTEGER := 0;
BEGIN
    PERFORM public.fx_require_admin();

    SELECT COUNT(DISTINCT user_id) INTO v_exposed
    FROM public.trades WHERE status IN ('open', 'pending');

    FOR v_uid IN
        SELECT a.user_id
        FROM (SELECT DISTINCT user_id FROM public.trades WHERE status IN ('open', 'pending')) a
        LEFT JOIN public.account_sweep_state s ON s.user_id = a.user_id
        ORDER BY s.last_evaluated_at ASC NULLS FIRST, a.user_id
        LIMIT GREATEST(COALESCE(p_max_accounts, 500), 1)
    LOOP
        BEGIN
            v_res := public.fx_evaluate_account(v_uid, NULL);
            v_accounts  := v_accounts + 1;
            v_closed    := v_closed + jsonb_array_length(v_res -> 'closed');
            v_triggered := v_triggered + jsonb_array_length(v_res -> 'triggered');
        EXCEPTION WHEN OTHERS THEN
            -- One bad account must neither abort the sweep nor starve the queue.
            v_errors := v_errors + 1;
            INSERT INTO public.account_sweep_state (user_id, last_evaluated_at, last_error, error_count)
            VALUES (v_uid, NOW(), LEFT(SQLERRM, 500), 1)
            ON CONFLICT (user_id) DO UPDATE
                SET last_evaluated_at = NOW(),
                    last_error        = EXCLUDED.last_error,
                    error_count       = public.account_sweep_state.error_count + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'accounts_with_exposure', v_exposed,
        'accounts_evaluated', v_accounts,
        'positions_closed', v_closed,
        'orders_triggered', v_triggered,
        'errors', v_errors,
        'swept_at', NOW());
END;
$$;

-- ------------------------------------------------------------------------------
-- GRANTS (re-asserted; internal primitives stay unreachable from clients)
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fx_close_trade_row(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_evaluate_account(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_sweep_accounts(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_accounts(INTEGER) TO service_role;

-- ------------------------------------------------------------------------------
-- DEPLOYED-VERSION MARKER (no longer reveals the admin head-count to anon).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_engine_version()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'engine', '2026-10-02.1',
        'uuid_source', 'gen_random_uuid',
        'kyc_module', public.fx_kyc_module_installed(),
        'manual_deposits', to_regclass('public.deposit_requests') IS NOT NULL,
        'client_quotes', (SELECT allow_client_quotes FROM public.broker_config WHERE id = 1),
        'require_kyc_for_trading', (SELECT require_kyc_for_trading FROM public.broker_config WHERE id = 1),
        'instruments', (SELECT COUNT(*) FROM public.instruments)
    );
$$;

GRANT EXECUTE ON FUNCTION public.fx_engine_version() TO authenticated, anon, service_role;

-- ==== END 20261002000400_engine_correctness.sql ====


-- Make PostgREST see the new table / columns / functions immediately.
NOTIFY pgrst, 'reload schema';
