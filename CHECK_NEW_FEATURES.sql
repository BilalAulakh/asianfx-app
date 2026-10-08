-- ==============================================================================
-- CHECK_NEW_FEATURES.sql — run in the Supabase SQL Editor AFTER:
--   APPLY_USER_DELETE_DEPOSIT.sql, APPLY_ADMIN_LIST_USERS.sql,
--   APPLY_WITHDRAW_ON_APPROVAL.sql
-- Read-only. Every row should say ok = true.
-- ==============================================================================

SELECT 'rpc_delete_my_deposit_request exists' AS check_name,
       to_regprocedure('public.rpc_delete_my_deposit_request(uuid)') IS NOT NULL AS ok
UNION ALL
SELECT 'deposit_requests.user_hidden_at exists',
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'deposit_requests'
                 AND column_name = 'user_hidden_at')
UNION ALL
SELECT 'users may read deposit_requests.user_hidden_at',
       has_column_privilege('authenticated', 'public.deposit_requests', 'user_hidden_at', 'SELECT')
UNION ALL
SELECT 'rpc_admin_list_users exists',
       to_regprocedure('public.rpc_admin_list_users()') IS NOT NULL
UNION ALL
SELECT 'withdrawals.funds_held exists',
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'withdrawals'
                 AND column_name = 'funds_held')
UNION ALL
SELECT 'request no longer deducts (no wallet UPDATE in rpc_request_withdrawal)',
       position('UPDATE public.wallets' IN
                pg_get_functiondef('public.rpc_request_withdrawal(numeric,text,text,text)'::regprocedure)) = 0
UNION ALL
SELECT 'approval deducts (funds_held branch in rpc_admin_review_withdrawal)',
       position('funds_held' IN
                pg_get_functiondef('public.rpc_admin_review_withdrawal(uuid,boolean,text,text,text)'::regprocedure)) > 0
UNION ALL
SELECT 'users can call the user RPCs',
       has_function_privilege('authenticated', 'public.rpc_delete_my_deposit_request(uuid)', 'EXECUTE')
   AND has_function_privilege('authenticated', 'public.rpc_request_withdrawal(numeric,text,text,text)', 'EXECUTE');

-- Pending withdrawals right now: old ones were deducted when made (funds_held = true),
-- new ones are deducted on approval (funds_held = false).
SELECT funds_held, COUNT(*) AS pending_requests, COALESCE(SUM(amount), 0) AS total
FROM public.withdrawals WHERE status = 'PENDING' GROUP BY funds_held;
