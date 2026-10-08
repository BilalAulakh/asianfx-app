-- ==============================================================================
-- MIGRATION: 20261008000300_admin_list_users.sql
--
-- Admin desk: the real list of registered traders.
-- The app used to count traders from a list cached on the admin's own device
-- plus rows of public.wallets (only users who already had a wallet, with made-up
-- names), so "Registered traders" / "Trader CRM" were wrong. This RPC reads
-- every account from auth.users (broker admins excluded) with its name and
-- phone from sign-up, wallet balance / frozen flag and KYC status.
--
-- Admin only (fx_require_admin). Idempotent.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_admin_list_users()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_out JSONB;
BEGIN
    PERFORM public.fx_require_admin();

    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::JSONB)
      INTO v_out
    FROM (
        SELECT u.created_at,
               jsonb_build_object(
                   'id',              u.id::TEXT,
                   'email',           u.email,
                   'full_name',       COALESCE(NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                                               NULLIF(btrim(u.raw_user_meta_data ->> 'name'), '')),
                   'phone',           COALESCE(NULLIF(btrim(u.raw_user_meta_data ->> 'phone'), ''),
                                               NULLIF(btrim(u.phone), '')),
                   'created_at',      u.created_at,
                   'last_sign_in_at', u.last_sign_in_at,
                   'email_confirmed', u.email_confirmed_at IS NOT NULL,
                   'balance',         COALESCE(w.balance, 0),
                   'is_frozen',       COALESCE(w.is_frozen, FALSE),
                   'kyc_status',      COALESCE(k.status, 'NOT_STARTED')
               ) AS j
        FROM auth.users u
        LEFT JOIN public.wallets w
               ON w.user_id = u.id::TEXT AND w.currency = 'USD'
        LEFT JOIN public.kyc_profiles k
               ON k.user_id = u.id::TEXT
        WHERE u.deleted_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM public.broker_admins b WHERE b.user_id = u.id::TEXT)
          AND COALESCE(u.raw_app_meta_data  ->> 'role', '') NOT IN ('admin', 'superadmin')
          AND COALESCE(u.raw_user_meta_data ->> 'role', '') NOT IN ('admin', 'superadmin')
    ) x;

    RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_list_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_admin_list_users() TO authenticated;

NOTIFY pgrst, 'reload schema';
