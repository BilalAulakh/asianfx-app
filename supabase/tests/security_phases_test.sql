-- ##############################################################################
--  supabase/tests/security_phases_test.sql
--
--  Regression tests for migrations 20261002000000 .. 20261002000400.
--
--  RUN ONLY AGAINST A LOCAL / STAGING DATABASE (e.g. `supabase start`, then
--  `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" -f supabase/tests/security_phases_test.sql`).
--  Everything happens inside one transaction that is ROLLED BACK at the end,
--  so no row survives — but never point it at production anyway.
--
--  Each block RAISEs on failure (the script stops with an error) and prints
--  NOTICE 'PASS: ...' on success. Requires the migrations to be applied and a
--  psql session as `postgres`.
-- ##############################################################################

\set ON_ERROR_STOP on
BEGIN;

-- ------------------------------------------------------------------------------
-- Test helpers (created inside the transaction -> rolled back with it)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._t_as(p_uid TEXT, p_extra JSONB DEFAULT '{}'::JSONB)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_uid IS NULL THEN
        PERFORM set_config('request.jwt.claims', '', TRUE);
        PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    ELSE
        PERFORM set_config('request.jwt.claims',
            (jsonb_build_object('sub', p_uid, 'role', 'authenticated') || p_extra)::TEXT, TRUE);
        PERFORM set_config('request.jwt.claim.sub', p_uid, TRUE);
    END IF;
END $$;

-- Run p_sql and require it to fail with a message starting with p_prefix.
CREATE OR REPLACE FUNCTION public._t_expect_error(p_sql TEXT, p_prefix TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE p_prefix || '%' THEN
            RETURN;
        END IF;
        RAISE EXCEPTION 'TEST FAILED: % -> expected "%..." but got "%"', p_sql, p_prefix, SQLERRM;
    END;
    RAISE EXCEPTION 'TEST FAILED: % -> expected error "%..." but it succeeded', p_sql, p_prefix;
END $$;

GRANT EXECUTE ON FUNCTION public._t_as(TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public._t_expect_error(TEXT, TEXT) TO authenticated;

-- ------------------------------------------------------------------------------
-- Fixtures (as postgres)
-- ------------------------------------------------------------------------------
SELECT set_config('t.admin', gen_random_uuid()::TEXT, TRUE),
       set_config('t.user',  gen_random_uuid()::TEXT, TRUE),
       set_config('t.user2', gen_random_uuid()::TEXT, TRUE);

INSERT INTO public.broker_admins (user_id, note, added_by)
VALUES (current_setting('t.admin'), 'test fixture', 'security_phases_test');

UPDATE public.broker_config
   SET deposit_address_trc20 = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV',
       min_deposit_usd       = 10
 WHERE id = 1;

-- Swap rates for the wiring test.
UPDATE public.instruments SET swap_long_per_lot = 2.5, swap_short_per_lot = -1.0 WHERE symbol = 'EUR/USD';

-- ==============================================================================
-- 1. ADMIN PRIVILEGE ESCALATION
-- ==============================================================================
SET LOCAL ROLE authenticated;

DO $$
DECLARE v JSONB;
BEGIN
    -- user_metadata.role = admin must NOT make anyone an admin.
    PERFORM public._t_as(current_setting('t.user'), '{"user_metadata": {"role": "admin"}}');
    ASSERT NOT public.fx_is_admin(), 'user_metadata.role=admin granted admin';
    v := public.rpc_whoami();
    ASSERT (v ->> 'is_admin')::BOOLEAN = FALSE, 'rpc_whoami reported admin for a metadata-only admin';
    ASSERT v ->> 'user_id' = current_setting('t.user'), 'rpc_whoami returned the wrong user';

    -- broker_admins row => admin.
    PERFORM public._t_as(current_setting('t.admin'));
    ASSERT public.fx_is_admin(), 'broker_admins member is not admin';

    -- app_metadata.role (service-key only) => admin.
    PERFORM public._t_as(current_setting('t.user2'), '{"app_metadata": {"role": "admin"}}');
    ASSERT public.fx_is_admin(), 'app_metadata.role=admin is not admin';

    RAISE NOTICE 'PASS: fx_is_admin ignores user_metadata; broker_admins / app_metadata work';
END $$;

DO $$
BEGIN
    PERFORM public._t_as(current_setting('t.user'), '{"user_metadata": {"role": "admin"}}');
    PERFORM public._t_expect_error(format('SELECT public.rpc_review_deposit(%L::uuid, true, 1)', gen_random_uuid()), 'FORBIDDEN');
    PERFORM public._t_expect_error('SELECT public.rpc_admin_list_deposit_requests()', 'FORBIDDEN');
    PERFORM public._t_expect_error('SELECT public.rpc_admin_set_markup(''EUR/USD'', 1)', 'FORBIDDEN');
    PERFORM public._t_expect_error('SELECT public.rpc_admin_set_spread_multiplier(2)', 'FORBIDDEN');
    PERFORM public._t_expect_error(format('SELECT public.rpc_admin_adjust_balance(%L, 1000, ''x'')', current_setting('t.user')), 'FORBIDDEN');
    PERFORM public._t_expect_error(
        format('SELECT public.rpc_review_kyc(%L, ''APPROVE'')', gen_random_uuid()), 'FORBIDDEN');
    RAISE NOTICE 'PASS: non-admin is refused by every admin RPC';
END $$;

-- ==============================================================================
-- 2. DEPOSIT SUBMISSION
-- ==============================================================================
DO $$
DECLARE
    v_uid TEXT := current_setting('t.user');
    v JSONB;
    v2 JSONB;
BEGIN
    PERFORM public._t_as(v_uid);

    v := public.rpc_submit_deposit_request(100, repeat('ab', 32), NULL, v_uid || '/proof.png', 'req-1');
    ASSERT v ->> 'status' = 'success', 'submit failed: ' || v::TEXT;
    ASSERT (v -> 'deposit') ->> 'status' = 'PENDING', 'new deposit is not PENDING';
    ASSERT NOT (v -> 'deposit') ? 'admin_note', 'admin_note leaked to the depositor';
    PERFORM set_config('t.dep1', (v -> 'deposit') ->> 'id', TRUE);

    -- Idempotent on request id.
    v2 := public.rpc_submit_deposit_request(100, repeat('ab', 32), NULL, NULL, 'req-1');
    ASSERT v2 ->> 'status' = 'duplicate', 'retry with the same request id was not idempotent';
    ASSERT (v2 -> 'deposit') ->> 'id' = (v -> 'deposit') ->> 'id', 'retry returned a different row';

    -- Same TXID again (any case) is refused.
    PERFORM public._t_expect_error(format('SELECT public.rpc_submit_deposit_request(100, %L, NULL, NULL, ''req-2'')', repeat('AB', 32)), 'TXID_ALREADY_USED');

    -- Validation.
    PERFORM public._t_expect_error('SELECT public.rpc_submit_deposit_request(100, ''nothex'')', 'BAD_TXID');
    PERFORM public._t_expect_error(format('SELECT public.rpc_submit_deposit_request(5, %L)', repeat('cd', 32)), 'AMOUNT_TOO_SMALL');
    PERFORM public._t_expect_error(format('SELECT public.rpc_submit_deposit_request(50, %L, ''0xdead'')', repeat('cd', 32)), 'BAD_ADDRESS');
    PERFORM public._t_expect_error(
        format('SELECT public.rpc_submit_deposit_request(50, %L, NULL, %L)', repeat('cd', 32), current_setting('t.user2') || '/x.png'),
        'BAD_PROOF_PATH');
    PERFORM public._t_expect_error(
        format('SELECT public.rpc_submit_deposit_request(50, %L, NULL, %L)', repeat('cd', 32), v_uid || '/../x.png'),
        'BAD_PROOF_PATH');

    RAISE NOTICE 'PASS: deposit submit validates, is idempotent and refuses reused TXIDs';
END $$;

DO $$
DECLARE i INTEGER;
BEGIN
    PERFORM public._t_as(current_setting('t.user'));
    -- Already 1 pending; 4 more reach the cap of 5; the 6th is refused.
    FOR i IN 1..4 LOOP
        PERFORM public.rpc_submit_deposit_request(20, repeat(to_hex(i), 64 / length(to_hex(i))), NULL, NULL, 'cap-' || i);
    END LOOP;
    PERFORM public._t_expect_error(format('SELECT public.rpc_submit_deposit_request(20, %L)', repeat('ef', 32)), 'TOO_MANY_PENDING');
    RAISE NOTICE 'PASS: max 5 pending deposit requests per user';
END $$;

-- The client cannot write the table, nor read the internal review columns.
DO $$
BEGIN
    PERFORM public._t_as(current_setting('t.user'));
    PERFORM public._t_expect_error(
        format('INSERT INTO public.deposit_requests (user_id, amount_claimed, txid) VALUES (%L, 1, %L)',
               current_setting('t.user'), repeat('99', 32)),
        'permission denied');
    PERFORM public._t_expect_error('UPDATE public.deposit_requests SET status = ''APPROVED''', 'permission denied');
    PERFORM public._t_expect_error('SELECT admin_note FROM public.deposit_requests', 'permission denied');
    PERFORM public._t_expect_error('SELECT public.credit_verified_deposit(''x'', ''y'', 1)', 'permission denied');
    RAISE NOTICE 'PASS: deposit_requests is read-only for clients; credit_verified_deposit is unreachable';
END $$;

-- ==============================================================================
-- 3. DEPOSIT REVIEW
-- ==============================================================================

-- Self-approval: the admin files a deposit and tries to approve it.
DO $$
DECLARE v JSONB;
BEGIN
    PERFORM public._t_as(current_setting('t.admin'));
    v := public.rpc_submit_deposit_request(500, repeat('a1', 32));
    PERFORM public._t_expect_error(
        format('SELECT public.rpc_review_deposit(%L::uuid, true, 500)', (v -> 'deposit') ->> 'id'),
        'SELF_REVIEW_FORBIDDEN');
    RAISE NOTICE 'PASS: an admin cannot approve their own deposit';
END $$;

DO $$
DECLARE
    v_dep   UUID := current_setting('t.dep1')::UUID;
    v_uid   TEXT := current_setting('t.user');
    v       JSONB;
    v_bal0  NUMERIC;
    v_bal1  NUMERIC;
    v_n     INTEGER;
BEGIN
    PERFORM public._t_as(current_setting('t.admin'));

    -- Admin queue includes the depositor e-mail field and puts PENDING first.
    v := public.rpc_admin_list_deposit_requests();
    ASSERT jsonb_array_length(v) >= 1 AND (v -> 0) ->> 'status' = 'PENDING', 'admin queue is not PENDING-first';
    ASSERT (v -> 0) ? 'user_email', 'admin queue has no user_email';

    PERFORM public._t_expect_error(format('SELECT public.rpc_review_deposit(%L::uuid, true, 0)', v_dep), 'BAD_AMOUNT');
    PERFORM public._t_expect_error(format('SELECT public.rpc_review_deposit(%L::uuid, true, NULL)', v_dep), 'BAD_AMOUNT');

    SELECT COALESCE(SUM(balance), 0) INTO v_bal0 FROM public.wallets WHERE user_id = v_uid AND currency = 'USD';

    -- Approve with the amount actually seen on-chain (differs from the claim).
    v := public.rpc_review_deposit(v_dep, TRUE, 95.5, NULL, 'fee deducted by sender exchange');
    ASSERT v ->> 'status' = 'success', 'approve failed: ' || v::TEXT;
    ASSERT (v -> 'deposit') ->> 'status' = 'APPROVED', 'deposit not APPROVED';
    ASSERT ((v -> 'deposit') ->> 'amount_credited')::NUMERIC = 95.5, 'wrong amount_credited';
    ASSERT (v -> 'deposit') ->> 'reviewed_by' = current_setting('t.admin'), 'reviewed_by not recorded';

    SELECT balance INTO v_bal1 FROM public.wallets WHERE user_id = v_uid AND currency = 'USD';
    ASSERT v_bal1 = v_bal0 + 95.5, format('wallet not credited: %s -> %s', v_bal0, v_bal1);
    ASSERT (v ->> 'new_balance')::NUMERIC = v_bal1, 'returned new_balance mismatch';

    SELECT COUNT(*) INTO v_n FROM public.ledger_entries
    WHERE idempotency_key = 'deposit:' || v_dep::TEXT AND type = 'deposit' AND amount = 95.5;
    ASSERT v_n = 1, 'expected exactly one deposit ledger entry';

    -- Double review: approve again, then try to reject. Nothing moves.
    v := public.rpc_review_deposit(v_dep, TRUE, 95.5);
    ASSERT v ->> 'status' = 'already_reviewed', 'second approve was not refused';
    v := public.rpc_review_deposit(v_dep, FALSE, NULL, 'changed my mind');
    ASSERT v ->> 'status' = 'already_reviewed', 'reject after approve was not refused';

    SELECT balance INTO v_bal1 FROM public.wallets WHERE user_id = v_uid AND currency = 'USD';
    ASSERT v_bal1 = v_bal0 + 95.5, 'double review moved money';
    SELECT COUNT(*) INTO v_n FROM public.ledger_entries WHERE idempotency_key = 'deposit:' || v_dep::TEXT;
    ASSERT v_n = 1, 'double review posted a second ledger entry';

    RAISE NOTICE 'PASS: approve credits once, records reviewer + ledger; double review is a no-op';
END $$;

DO $$
DECLARE
    v_uid  TEXT := current_setting('t.user2');
    v      JSONB;
    v_dep  UUID;
    v_bal0 NUMERIC;
    v_bal1 NUMERIC;
BEGIN
    PERFORM public._t_as(v_uid);
    v := public.rpc_submit_deposit_request(42, repeat('b2', 32));
    v_dep := ((v -> 'deposit') ->> 'id')::UUID;

    PERFORM public._t_as(current_setting('t.admin'));
    SELECT COALESCE(SUM(balance), 0) INTO v_bal0 FROM public.wallets WHERE user_id = v_uid;

    PERFORM public._t_expect_error(format('SELECT public.rpc_review_deposit(%L::uuid, false, NULL, ''  '')', v_dep), 'REASON_REQUIRED');
    v := public.rpc_review_deposit(v_dep, FALSE, NULL, 'TXID not found on Tronscan');
    ASSERT (v -> 'deposit') ->> 'status' = 'REJECTED', 'deposit not REJECTED';
    ASSERT (v -> 'deposit') ->> 'reject_reason' = 'TXID not found on Tronscan', 'reason not stored';

    SELECT COALESCE(SUM(balance), 0) INTO v_bal1 FROM public.wallets WHERE user_id = v_uid;
    ASSERT v_bal1 = v_bal0, 'reject moved money';

    v := public.rpc_review_deposit(v_dep, TRUE, 42);
    ASSERT v ->> 'status' = 'already_reviewed', 'approve after reject was not refused';

    -- A rejected TXID can never be claimed again.
    PERFORM public._t_as(v_uid);
    PERFORM public._t_expect_error(format('SELECT public.rpc_submit_deposit_request(42, %L)', repeat('b2', 32)), 'TXID_ALREADY_USED');

    RAISE NOTICE 'PASS: reject needs a reason, moves no money, and burns the TXID';
END $$;

-- ==============================================================================
-- 4. KYC REQUIRED FOR TRADING
-- ==============================================================================
DO $$
BEGIN
    PERFORM public._t_as(current_setting('t.user'));
    PERFORM public._t_expect_error(
        'SELECT public.rpc_open_trade(''EUR/USD'', ''buy'', ''market'', 0.01, 100)', 'KYC_REQUIRED');
    RAISE NOTICE 'PASS: trading requires approved KYC';
END $$;

-- ==============================================================================
-- 5. ENGINE (as postgres: fixtures are written directly)
-- ==============================================================================
RESET ROLE;
SELECT public._t_as(NULL);

-- Fresh publisher quote, far BELOW a long's stop loss (a gap).
INSERT INTO public.market_quotes (symbol, bid, ask, quote_to_usd, source, updated_at)
VALUES ('EUR/USD', 1.09000, 1.09020, 1, 'publisher', NOW())
ON CONFLICT (symbol) DO UPDATE
    SET bid = EXCLUDED.bid, ask = EXCLUDED.ask, quote_to_usd = 1, source = 'publisher', updated_at = NOW();

-- Stale publisher quote for a second symbol.
INSERT INTO public.market_quotes (symbol, bid, ask, quote_to_usd, source, updated_at)
VALUES ('GBP/USD', 1.20000, 1.20020, 1, 'publisher', NOW() - INTERVAL '1 hour')
ON CONFLICT (symbol) DO UPDATE
    SET bid = EXCLUDED.bid, ask = EXCLUDED.ask, quote_to_usd = 1, source = 'publisher', updated_at = EXCLUDED.updated_at;

INSERT INTO public.wallets (user_id, currency, balance, held_margin)
VALUES (current_setting('t.user2'), 'USD', 100000, 2200)
ON CONFLICT (user_id, currency) DO UPDATE SET balance = 100000, held_margin = 2200;

INSERT INTO public.trades (id, user_id, order_id, symbol, side, type, status, lots, contract_size,
                           open_price, current_price, stop_loss, required_margin, leverage,
                           quote_to_usd_rate, open_time, filled_at, created_at, updated_at)
VALUES
  ('T-GAP',   current_setting('t.user2'), 'O-GAP',   'EUR/USD', 'buy', 'market', 'open', 1, 100000,
   1.10000, 1.10000, 1.09500, 1100, 100, 1, NOW(), NOW(), NOW(), NOW()),
  ('T-STALE', current_setting('t.user2'), 'O-STALE', 'GBP/USD', 'buy', 'market', 'open', 1, 100000,
   1.30000, 1.30000, 1.25000, 1100, 100, 1, NOW(), NOW(), NOW(), NOW());

-- Pending SELL STOP at 1.0950; the gap put the bid at 1.0900.
INSERT INTO public.trades (id, user_id, order_id, symbol, side, type, status, lots, contract_size,
                           open_price, current_price, target_price, required_margin, leverage,
                           quote_to_usd_rate, open_time, created_at, updated_at)
VALUES ('T-PSTOP', current_setting('t.user2'), 'O-PSTOP', 'EUR/USD', 'sell', 'stop', 'pending', 0.1, 100000,
        1.09500, 1.09500, 1.09500, 0, 100, 1, NOW(), NOW(), NOW());

DO $$
DECLARE v JSONB; t public.trades;
BEGIN
    v := public.fx_evaluate_account(current_setting('t.user2'), NULL);

    SELECT * INTO t FROM public.trades WHERE id = 'T-GAP';
    ASSERT t.status = 'closed' AND t.close_reason = 'STOP_LOSS', 'gapped SL did not close: ' || t.status;
    ASSERT t.close_price = 1.09000, format('gap SL filled at %s, expected the bid 1.09000 (not the SL 1.09500)', t.close_price);

    SELECT * INTO t FROM public.trades WHERE id = 'T-STALE';
    ASSERT t.status = 'open', 'engine executed on a STALE quote';

    SELECT * INTO t FROM public.trades WHERE id = 'T-PSTOP';
    ASSERT t.status = 'open', 'pending sell stop did not trigger: ' || t.status;
    ASSERT t.open_price = 1.09000, format('pending stop filled at %s, expected the bid 1.09000', t.open_price);

    RAISE NOTICE 'PASS: SL and pending stops fill at the post-gap price; stale quotes are not executed';
END $$;

-- ---- Client quotes: never a price source, never persisted.
DO $$
DECLARE q public.fx_quote_t; m public.market_quotes;
BEGIN
    PERFORM public._t_expect_error(
        'SELECT public.fx_resolve_quote(''GBP/USD'', ''{"GBP/USD": {"bid": 1.2, "ask": 1.2002, "rate": 99}}''::jsonb, TRUE, TRUE)',
        'NO_QUOTE');

    q := public.fx_resolve_quote('EUR/USD', '{"EUR/USD": {"bid": 1.5, "ask": 1.5002, "rate": 99}}'::JSONB, TRUE, TRUE);
    ASSERT q.bid = 1.09000 AND q.source = 'publisher' AND q.quote_to_usd = 1, 'client quote influenced the price';

    SELECT * INTO m FROM public.market_quotes WHERE symbol = 'EUR/USD';
    ASSERT m.source = 'publisher' AND m.bid = 1.09000, 'client quote was persisted';

    RAISE NOTICE 'PASS: client quotes are ignored and never persisted; no fresh price => NO_QUOTE';
END $$;

-- ---- Swap rollover counting (2026-09-28 is a Monday).
DO $$
BEGIN
    ASSERT public.fx_swap_rollover_count('2026-09-28 20:00Z', '2026-09-28 22:00Z', 'forex', 21) = 1, 'Mon across rollover';
    ASSERT public.fx_swap_rollover_count('2026-09-28 21:10Z', '2026-09-29 20:50Z', 'forex', 21) = 0, '23h40m without crossing 21:00';
    ASSERT public.fx_swap_rollover_count('2026-09-29 20:00Z', '2026-09-30 22:00Z', 'forex', 21) = 4, 'Tue x1 + Wed x3';
    ASSERT public.fx_swap_rollover_count('2026-10-02 20:00Z', '2026-10-05 22:00Z', 'forex', 21) = 2, 'Fri + Mon, no weekend';
    ASSERT public.fx_swap_rollover_count('2026-10-02 20:00Z', '2026-10-05 22:00Z', 'crypto', 21) = 4, 'crypto every day';
    ASSERT public.fx_swap_rollover_count('2026-09-30 20:00Z', '2026-09-30 22:00Z', 'stocks', 21) = 1, 'stocks: no triple Wednesday';
    ASSERT public.fx_swap_rollover_count('2026-09-28 22:00Z', '2026-10-05 22:00Z', 'forex', 21) = 7, 'one full forex week = 7';
    ASSERT public.fx_swap_rollover_count('2026-09-28 22:00Z', '2026-09-28 20:00Z', 'forex', 21) = 0, 'reversed range';
    RAISE NOTICE 'PASS: swap counts rollovers at the configured hour with triple Wednesday';
END $$;

-- ---- Swap wiring: a long held 8 days pays rollovers * lots * swap_long_per_lot.
UPDATE public.wallets SET held_margin = held_margin + 1100 WHERE user_id = current_setting('t.user2');
INSERT INTO public.trades (id, user_id, order_id, symbol, side, type, status, lots, contract_size,
                           open_price, current_price, required_margin, leverage,
                           quote_to_usd_rate, open_time, filled_at, created_at, updated_at)
VALUES ('T-SWAP', current_setting('t.user2'), 'O-SWAP', 'EUR/USD', 'buy', 'market', 'open', 2, 100000,
        1.09000, 1.09000, 1100, 100, 1, NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days', NOW(), NOW());

DO $$
DECLARE v JSONB; v_rolls INTEGER;
BEGIN
    SELECT public.fx_swap_rollover_count(filled_at, NOW(), 'forex', 21) INTO v_rolls
    FROM public.trades WHERE id = 'T-SWAP';
    ASSERT v_rolls >= 7, 'an 8-day hold must cross at least 7 weighted rollovers';

    v := public.fx_close_trade_row('T-SWAP', 1.09000, 1.09000, 1.09020, 1, 'MANUAL', 'publisher');
    ASSERT (v ->> 'rollovers')::INTEGER = v_rolls, 'close used a different rollover count';
    ASSERT (v ->> 'swap')::NUMERIC = v_rolls * 2 * 2.5, format('swap %s, expected %s', v ->> 'swap', v_rolls * 5);
    RAISE NOTICE 'PASS: swap is charged per rollover on close';
END $$;

-- ---- Fair sweep: the never-evaluated account goes before a recently evaluated one.
INSERT INTO public.trades (id, user_id, order_id, symbol, side, type, status, lots, contract_size,
                           open_price, current_price, target_price, required_margin, leverage,
                           quote_to_usd_rate, open_time, created_at, updated_at)
VALUES ('T-FAIR', current_setting('t.user'), 'O-FAIR', 'EUR/USD', 'buy', 'limit', 'pending', 0.01, 100000,
        0.50000, 0.50000, 0.50000, 0, 100, 1, NOW(), NOW(), NOW());

DELETE FROM public.account_sweep_state
 WHERE user_id IN (current_setting('t.user'), current_setting('t.user2'));
INSERT INTO public.account_sweep_state (user_id, last_evaluated_at)
VALUES (current_setting('t.user2'), NOW() - INTERVAL '10 minutes');
-- Make everyone else look freshly swept so only our two accounts compete.
UPDATE public.account_sweep_state SET last_evaluated_at = NOW()
 WHERE user_id NOT IN (current_setting('t.user'), current_setting('t.user2'));
INSERT INTO public.account_sweep_state (user_id, last_evaluated_at)
SELECT DISTINCT t.user_id, NOW() FROM public.trades t
WHERE t.status IN ('open', 'pending')
  AND t.user_id NOT IN (current_setting('t.user'), current_setting('t.user2'))
ON CONFLICT (user_id) DO NOTHING;

DO $$
DECLARE v JSONB; v_at TIMESTAMPTZ; v_at2 TIMESTAMPTZ;
BEGIN
    v := public.rpc_sweep_accounts(1);
    SELECT last_evaluated_at INTO v_at  FROM public.account_sweep_state WHERE user_id = current_setting('t.user');
    SELECT last_evaluated_at INTO v_at2 FROM public.account_sweep_state WHERE user_id = current_setting('t.user2');
    ASSERT v_at IS NOT NULL, 'never-evaluated account was skipped';
    ASSERT v_at2 < NOW() - INTERVAL '5 minutes', 'recently evaluated account went first';

    v := public.rpc_sweep_accounts(1);
    SELECT last_evaluated_at INTO v_at2 FROM public.account_sweep_state WHERE user_id = current_setting('t.user2');
    ASSERT v_at2 > NOW() - INTERVAL '1 minute', 'second sweep did not reach the next-oldest account';
    RAISE NOTICE 'PASS: rpc_sweep_accounts covers accounts oldest-first';
END $$;

-- ---- Dealer markup is clamped and audited.
DO $$
DECLARE v JSONB; v_n INTEGER;
BEGIN
    PERFORM public._t_as(current_setting('t.admin'));
    v := public.rpc_admin_set_markup('EUR/USD', 9999);
    ASSERT (v ->> 'spread_markup_points')::INTEGER = 500, 'markup not clamped to 500';
    v := public.rpc_admin_set_spread_multiplier(0.2);
    ASSERT (v ->> 'spread_multiplier')::NUMERIC = 1, 'multiplier not clamped to 1';
    SELECT COUNT(*) INTO v_n FROM public.admin_config_audit WHERE admin_id = current_setting('t.admin');
    ASSERT v_n >= 1, 'dealer change not audited';
    RAISE NOTICE 'PASS: dealer markup / multiplier are clamped and audited';
END $$;

ROLLBACK;
\echo 'security_phases_test.sql: all checks passed (transaction rolled back)'
