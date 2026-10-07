-- ==============================================================================
-- MIGRATION: 20261007000100_performance.sql
--
-- 1. RLS: evaluate auth.uid() / fx_is_admin() ONCE per query, not once per row.
--    A bare function call in a policy is re-run for every row scanned;
--    fx_is_admin() also queries broker_admins each time. Wrapped in a scalar
--    sub-select, Postgres computes it once (InitPlan) and reuses the result.
--    This is Supabase's documented RLS optimisation. ALTER POLICY changes only
--    the expressions; each policy keeps its name, command and roles, and the
--    rules are logically identical.
-- 2. Index for a user's trade history (all / closed trades, newest first); the
--    existing trades index only covers open and pending rows.
--
-- Idempotent. A policy or table that does not exist is skipped with a NOTICE.
-- ==============================================================================

DO $$
DECLARE
    v_sql TEXT;
BEGIN
    FOREACH v_sql IN ARRAY ARRAY[
        -- deposits (legacy)
        $p$ALTER POLICY "Users can view own deposits" ON public.deposits
            USING ((SELECT auth.uid())::text = user_id::text)$p$,
        -- wallets
        $p$ALTER POLICY "wallets_select_own" ON public.wallets
            USING ((SELECT auth.uid())::text = user_id)$p$,
        $p$ALTER POLICY "wallets_select_admin" ON public.wallets
            USING ((SELECT public.fx_is_admin()))$p$,
        -- trades / ledger / withdrawals / adjustments
        $p$ALTER POLICY "trades_select_own" ON public.trades
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "ledger_select_own" ON public.ledger_entries
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "withdrawals_select_own" ON public.withdrawals
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "admin_adj_select_admin" ON public.admin_balance_adjustments
            USING ((SELECT public.fx_is_admin()) OR (SELECT auth.uid())::text = user_id)$p$,
        -- KYC
        $p$ALTER POLICY "kyc_profiles_select" ON public.kyc_profiles
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "kyc_profiles_insert_own" ON public.kyc_profiles
            WITH CHECK ((SELECT auth.uid())::text = user_id)$p$,
        $p$ALTER POLICY "kyc_profiles_update_own" ON public.kyc_profiles
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))
            WITH CHECK ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "kyc_documents_select" ON public.kyc_documents
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "kyc_documents_insert_own" ON public.kyc_documents
            WITH CHECK ((SELECT auth.uid())::text = user_id)$p$,
        $p$ALTER POLICY "kyc_documents_update" ON public.kyc_documents
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))
            WITH CHECK ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "kyc_audit_select" ON public.kyc_audit_logs
            USING ((SELECT auth.uid())::text = user_id OR (SELECT public.fx_is_admin()))$p$,
        -- deposit requests / admin audit
        $p$ALTER POLICY "deposit_requests_select_own" ON public.deposit_requests
            USING ((SELECT auth.uid())::text = user_id)$p$,
        $p$ALTER POLICY "deposit_requests_select_admin" ON public.deposit_requests
            USING ((SELECT public.fx_is_admin()))$p$,
        $p$ALTER POLICY "admin_config_audit_select_admin" ON public.admin_config_audit
            USING ((SELECT public.fx_is_admin()))$p$,
        -- storage (KYC documents, deposit screenshots)
        $p$ALTER POLICY "Users can upload their own KYC docs" ON storage.objects
            WITH CHECK (bucket_id = 'kyc-documents'
                        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)$p$,
        $p$ALTER POLICY "Users and admins can view KYC docs" ON storage.objects
            USING (bucket_id = 'kyc-documents'
                   AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text
                        OR (SELECT public.fx_is_admin())))$p$,
        $p$ALTER POLICY "deposit_proofs_insert_own" ON storage.objects
            WITH CHECK (bucket_id = 'deposit-proofs'
                        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)$p$,
        $p$ALTER POLICY "deposit_proofs_select_own_or_admin" ON storage.objects
            USING (bucket_id = 'deposit-proofs'
                   AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text
                        OR (SELECT public.fx_is_admin())))$p$
    ]
    LOOP
        BEGIN
            EXECUTE v_sql;
        EXCEPTION
            WHEN undefined_object OR undefined_table OR insufficient_privilege THEN
                RAISE NOTICE 'skipped: % (%)', split_part(v_sql, ' ON ', 1), SQLERRM;
        END;
    END LOOP;
END $$;

-- A user's trade history, newest first (SupabaseTradeService: all trades and
-- closed trades by user_id ORDER BY created_at DESC).
CREATE INDEX IF NOT EXISTS idx_trades_user_created
    ON public.trades (user_id, created_at DESC);

-- Fresh planner statistics for the tables above.
ANALYZE public.trades;
ANALYZE public.ledger_entries;
ANALYZE public.deposit_requests;
ANALYZE public.withdrawals;
