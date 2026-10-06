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
