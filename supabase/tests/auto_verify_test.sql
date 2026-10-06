-- ##############################################################################
--  supabase/tests/auto_verify_test.sql
--
--  Regression tests for 20261006000100_auto_verify_deposits.sql: weighted
--  rotation (A,A,A,B), address_used, WAITING vs NOT_REQUIRED, system approval
--  (on-chain amount, exactly once, recipient check, limit), system RPC
--  permissions, admin Pending / Auto-approved filters.
--
--  RUN ONLY AGAINST A LOCAL / STAGING DATABASE, as `postgres`:
--    psql "$DB_URL" -f supabase/tests/auto_verify_test.sql
--  Everything runs in one transaction that is ROLLED BACK at the end.
--  Each block RAISEs on failure and prints NOTICE 'PASS: ...' on success.
-- ##############################################################################

\set ON_ERROR_STOP on
BEGIN;

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

CREATE OR REPLACE FUNCTION public._t_expect_error(p_sql TEXT, p_prefix TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE p_prefix || '%' OR SQLSTATE = '42501' AND p_prefix = 'PERMISSION' THEN
            RETURN;
        END IF;
        RAISE EXCEPTION 'TEST FAILED: % -> expected "%..." but got "%"', p_sql, p_prefix, SQLERRM;
    END;
    RAISE EXCEPTION 'TEST FAILED: % -> expected error "%..." but it succeeded', p_sql, p_prefix;
END $$;

GRANT EXECUTE ON FUNCTION public._t_as(TEXT, JSONB) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._t_expect_error(TEXT, TEXT) TO authenticated, anon;

-- ------------------------------------------------------------------------------
-- Fixtures (as postgres): exactly the two spec addresses, rotation from slot 0.
-- ------------------------------------------------------------------------------
SELECT set_config('t.admin', gen_random_uuid()::TEXT, TRUE);
DO $$
BEGIN
    FOR i IN 1..12 LOOP
        PERFORM set_config('t.u' || i, gen_random_uuid()::TEXT, TRUE);
        INSERT INTO public.wallets (user_id, currency, balance, held_margin)
        VALUES (current_setting('t.u' || i), 'USD', 0, 0) ON CONFLICT DO NOTHING;
    END LOOP;
END $$;

INSERT INTO public.broker_admins (user_id, note, added_by)
VALUES (current_setting('t.admin'), 'test fixture', 'auto_verify_test');

UPDATE public.company_deposit_addresses SET is_active = FALSE
 WHERE address NOT IN ('TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS');
UPDATE public.company_deposit_addresses
   SET is_active = TRUE, weight = CASE WHEN auto_verify THEN 1 ELSE 3 END
 WHERE address IN ('TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS');
UPDATE public.deposit_rotation_state SET counter = 0 WHERE id = 1;
UPDATE public.broker_config SET min_deposit_usd = 10 WHERE id = 1;

-- ==============================================================================
-- 1. CONFIGURATION
-- ==============================================================================
DO $$
DECLARE a public.company_deposit_addresses; b public.company_deposit_addresses;
BEGIN
    SELECT * INTO a FROM public.company_deposit_addresses WHERE address = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV';
    SELECT * INTO b FROM public.company_deposit_addresses WHERE address = 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS';
    ASSERT NOT a.auto_verify, 'Address A must be manual';
    ASSERT b.auto_verify AND b.max_auto_approve_usd = 1000, 'Address B must be automatic, limit 1000';
    RAISE NOTICE 'PASS: Address A manual, Address B automatic ($1000)';
END $$;

-- ==============================================================================
-- 2. ROTATION A,A,A,B x3 + address_used + verification_status + no override
-- ==============================================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE
    v       JSONB;
    v_seq   TEXT := '';
    v_want  TEXT := 'AAABAAABAAAB';
    v_dep   JSONB;
BEGIN
    FOR i IN 1..12 LOOP
        PERFORM public._t_as(current_setting('t.u' || i));
        v := public.rpc_create_deposit_request(100, 'rot-' || i);
        v_dep := v -> 'deposit';
        v_seq := v_seq || CASE v_dep ->> 'address_used'
                             WHEN 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV' THEN 'A'
                             WHEN 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS' THEN 'B' ELSE '?' END;
        ASSERT v_dep ->> 'verification_status' =
               CASE WHEN v_dep ->> 'address_used' = 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS' THEN 'WAITING' ELSE 'NOT_REQUIRED' END,
               format('wrong verification_status for request %s', i);
        PERFORM set_config('t.dep' || i, v_dep ->> 'id', TRUE);
    END LOOP;
    ASSERT v_seq = v_want, format('rotation was %s, expected %s', v_seq, v_want);

    -- There is no parameter through which a client could choose the address.
    ASSERT NOT EXISTS (
        SELECT 1 FROM information_schema.parameters
        WHERE specific_schema = 'public' AND specific_name LIKE 'rpc_create_deposit_request_%'
          AND parameter_name ILIKE '%address%'), 'client can pass an address';

    -- Asking again returns the same open request: no extra rotation slot.
    PERFORM public._t_as(current_setting('t.u1'));
    v := public.rpc_create_deposit_request(150, 'rot-1-again');
    ASSERT v ->> 'status' = 'existing' AND v -> 'deposit' ->> 'id' = current_setting('t.dep1'),
        'second request did not resume the open one';

    RAISE NOTICE 'PASS: rotation % ; address_used stored ; WAITING/NOT_REQUIRED ; no client override', v_seq;
END $$;
RESET ROLE;

-- Concurrency: the rotation row is locked FOR UPDATE inside fx_assign_deposit_address,
-- so concurrent transactions serialise on it and take consecutive slots.
DO $$
BEGIN
    ASSERT position('FOR UPDATE' IN pg_get_functiondef('public.fx_assign_deposit_address()'::regprocedure)) > 0,
        'rotation is not locked';
    RAISE NOTICE 'PASS: rotation state is row-locked (concurrency-safe)';
END $$;

-- ==============================================================================
-- 3. SYSTEM RPC PERMISSIONS
-- ==============================================================================
SET LOCAL ROLE authenticated;
DO $$
BEGIN
    PERFORM public._t_as(current_setting('t.u4'));
    PERFORM public._t_expect_error(format(
        'SELECT public.rpc_system_approve_deposit(%L::uuid, %L, 10, %L, NULL, 1)',
        current_setting('t.dep4'), repeat('a', 64), 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS'), 'permission denied');
    PERFORM public._t_expect_error(format(
        'SELECT public.rpc_system_mark_verification(%L::uuid, ''FAILED'', ''X'')', current_setting('t.dep4')),
        'permission denied');
    RAISE NOTICE 'PASS: authenticated users cannot call system RPCs';
END $$;
RESET ROLE;

SET LOCAL ROLE anon;
DO $$
BEGIN
    PERFORM public._t_as(NULL);
    PERFORM public._t_expect_error(format(
        'SELECT public.rpc_system_approve_deposit(%L::uuid, %L, 10, %L, NULL, 1)',
        current_setting('t.dep4'), repeat('a', 64), 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS'), 'permission denied');
    RAISE NOTICE 'PASS: anonymous callers cannot call system RPCs';
END $$;
RESET ROLE;

-- ==============================================================================
-- 4. SYSTEM APPROVAL (as postgres = backend)
-- ==============================================================================
DO $$
DECLARE v JSONB; d public.deposit_requests; bal NUMERIC; n INTEGER;
BEGIN
    -- 4a. Recipient mismatch is refused (and becomes manual review).
    v := public.rpc_system_approve_deposit(current_setting('t.dep8')::uuid, repeat('b', 64), 50,
                                           'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', NULL, 1);
    SELECT * INTO d FROM public.deposit_requests WHERE id = current_setting('t.dep8')::uuid;
    ASSERT v ->> 'reason' = 'WRONG_RECIPIENT' AND d.verification_status = 'FAILED' AND d.status = 'PENDING',
        'recipient mismatch not refused';
    SELECT balance INTO bal FROM public.wallets WHERE user_id = current_setting('t.u8');
    ASSERT bal = 0, 'wrong-recipient deposit was credited';

    -- 4b. Valid: on-chain amount (98.50, claimed 100) credited exactly once.
    v := public.rpc_system_approve_deposit(current_setting('t.dep4')::uuid, repeat('c', 64), 98.5,
                                           'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS', 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t', 66000000);
    ASSERT v ->> 'status' = 'success', 'valid approval failed: ' || v::TEXT;
    v := public.rpc_system_approve_deposit(current_setting('t.dep4')::uuid, repeat('c', 64), 98.5,
                                           'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS', NULL, 66000000);
    ASSERT v ->> 'status' = 'already_processed', 'repeat approval was not idempotent';
    SELECT * INTO d FROM public.deposit_requests WHERE id = current_setting('t.dep4')::uuid;
    SELECT balance INTO bal FROM public.wallets WHERE user_id = current_setting('t.u4');
    ASSERT bal = 98.5, format('balance %s, expected 98.5 (credited once, on-chain amount)', bal);
    ASSERT d.status = 'APPROVED' AND d.verification_status = 'VERIFIED' AND d.approved_by_system
           AND d.reviewed_by = 'system:auto-verify' AND d.amount_credited = 98.5 AND d.onchain_amount = 98.5,
        'approved row has wrong fields';
    SELECT COUNT(*) INTO n FROM public.ledger_entries WHERE idempotency_key = 'deposit:' || d.id::TEXT;
    ASSERT n = 1, format('%s ledger entries for one deposit', n);

    -- 4c. Above $1000: FAILED, not credited, manual review.
    v := public.rpc_system_approve_deposit(current_setting('t.dep12')::uuid, repeat('d', 64), 1500,
                                           'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS', NULL, 1);
    SELECT * INTO d FROM public.deposit_requests WHERE id = current_setting('t.dep12')::uuid;
    SELECT balance INTO bal FROM public.wallets WHERE user_id = current_setting('t.u12');
    ASSERT d.verification_status = 'FAILED' AND d.verification_error = 'ABOVE_AUTO_LIMIT'
           AND NOT d.approved_by_system AND bal = 0, 'above-limit deposit was not held for review';

    -- 4d. Address A deposits are never auto-approved.
    v := public.rpc_system_approve_deposit(current_setting('t.dep1')::uuid, repeat('e', 64), 10,
                                           'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', NULL, 1);
    ASSERT v ->> 'status' = 'already_processed', 'manual (NOT_REQUIRED) deposit was processed by the system';

    RAISE NOTICE 'PASS: recipient check, on-chain amount once, idempotent, limit, Address A untouched';
END $$;

-- 4e. Timeout -> FAILED -> visible to admins in Pending.
DO $$
DECLARE v JSONB;
BEGIN
    v := public.rpc_system_mark_verification(current_setting('t.dep4')::uuid, 'RETRY', NULL); -- already approved
    ASSERT v ->> 'status' = 'already_processed', 'mark on a processed deposit changed it';
    -- dep8 already FAILED; create a fresh waiting one via the rotation is covered above,
    -- so time out the remaining WAITING deposit directly.
    UPDATE public.deposit_requests SET verification_status = 'WAITING', verification_error = NULL
     WHERE id = current_setting('t.dep8')::uuid;
    v := public.rpc_system_mark_verification(current_setting('t.dep8')::uuid, 'FAILED', 'TIMEOUT');
    ASSERT v ->> 'verification_status' = 'FAILED', 'timeout was not recorded';
    RAISE NOTICE 'PASS: timeout moves the deposit to manual review';
END $$;

-- ==============================================================================
-- 5. ADMIN QUEUES
-- ==============================================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE pending JSONB; auto JSONB; ids TEXT[];
BEGIN
    PERFORM public._t_as(current_setting('t.admin'));
    pending := public.rpc_admin_list_deposit_requests('PENDING');
    SELECT array_agg(x ->> 'id') INTO ids FROM jsonb_array_elements(pending) x;

    ASSERT NOT (current_setting('t.dep4') = ANY(ids)), 'auto-approved deposit is in Pending';
    ASSERT current_setting('t.dep8') = ANY(ids), 'timed-out deposit is missing from Pending';
    ASSERT current_setting('t.dep12') = ANY(ids), 'above-limit deposit is missing from Pending';
    ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(pending) x WHERE x ->> 'verification_status' = 'WAITING'),
        'WAITING deposit is in Pending';
    ASSERT NOT (current_setting('t.dep1') = ANY(ids)), 'unpaid manual request (no proof) is in Pending';

    auto := public.rpc_admin_list_deposit_requests('AUTO_APPROVED');
    ASSERT jsonb_array_length(auto) >= 1
       AND (SELECT bool_and((x ->> 'approved_by_system')::BOOLEAN) FROM jsonb_array_elements(auto) x),
        'Auto-approved list is wrong';

    -- The admin cannot act on a deposit the system is still verifying.
    PERFORM public._t_expect_error(format('SELECT public.rpc_review_deposit(%L::uuid, true, 10)',
        (SELECT id FROM public.deposit_requests WHERE verification_status = 'WAITING' AND status = 'PENDING' LIMIT 1)),
        'AUTO_VERIFY_IN_PROGRESS');

    RAISE NOTICE 'PASS: Pending = human work only; Auto-approved is separate; no review while WAITING';
END $$;
RESET ROLE;

-- ==============================================================================
-- 6. ADMIN WALLET FIELD = ADDRESS A (20261006000200_admin_address_a.sql)
-- ==============================================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE
    v      JSONB;
    v_seq  TEXT := '';
    v_newA TEXT := 'TQn9Y2khEsLJW1ChVWFMSMeRDow5KcbLSE';
BEGIN
    PERFORM public._t_as(current_setting('t.admin'));
    -- Address B cannot be made Address A.
    PERFORM public._t_expect_error('SELECT public.rpc_admin_set_deposit_address(''TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS'')',
        'ADDRESS_IS_AUTOMATIC');
    v := public.rpc_admin_set_deposit_address(v_newA);
    ASSERT v ->> 'previous' = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV', 'previous Address A not reported';
    PERFORM set_config('t.newA', v_newA, TRUE);
END $$;
RESET ROLE;

-- Fresh users, rotation from slot 0: new A, new A, new A, B.
UPDATE public.deposit_rotation_state SET counter = 0 WHERE id = 1;
DO $$
BEGIN
    FOR i IN 13..20 LOOP
        PERFORM set_config('t.u' || i, gen_random_uuid()::TEXT, TRUE);
        INSERT INTO public.wallets (user_id, currency, balance, held_margin)
        VALUES (current_setting('t.u' || i), 'USD', 0, 0) ON CONFLICT DO NOTHING;
    END LOOP;
    ASSERT (SELECT deposit_address_trc20 FROM public.broker_config WHERE id = 1) = current_setting('t.newA'),
        'broker_config not mirrored';
    ASSERT NOT (SELECT is_active FROM public.company_deposit_addresses WHERE address = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV'),
        'old Address A still active';
END $$;

SET LOCAL ROLE authenticated;
DO $$
DECLARE v JSONB; v_seq TEXT := ''; a TEXT;
BEGIN
    FOR i IN 13..20 LOOP
        PERFORM public._t_as(current_setting('t.u' || i));
        v := public.rpc_create_deposit_request(100, 'rot2-' || i);
        a := v -> 'deposit' ->> 'address_used';
        v_seq := v_seq || CASE WHEN a = current_setting('t.newA') THEN 'A'
                               WHEN a = 'TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS' THEN 'B' ELSE '?' END;
    END LOOP;
    ASSERT v_seq = 'AAABAAAB', format('rotation after setting Address A was %s', v_seq);
    RAISE NOTICE 'PASS: admin wallet field sets Address A; rotation % ; B unchanged', v_seq;
END $$;
RESET ROLE;

ROLLBACK;
