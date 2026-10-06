-- ##############################################################################
--  CHECK_KYC.sql  —  read-only diagnostic. Paste into the Supabase SQL Editor
--  and Run. Changes nothing.
-- ##############################################################################

-- 1. Every KYC application stored on the server, newest first.
--    The user's "under review" application should be here as PENDING_REVIEW.
SELECT k.id, u.email, k.first_name, k.last_name, k.status, k.submitted_at,
       (SELECT COUNT(*) FROM public.kyc_documents d WHERE d.kyc_id = k.id) AS documents
  FROM public.kyc_profiles k
  LEFT JOIN auth.users u ON u.id::TEXT = k.user_id
 ORDER BY k.submitted_at DESC NULLS LAST;

-- 2. Accounts that count as administrators (and may read every application).
SELECT 'broker_admins' AS source, u.email
  FROM public.broker_admins b
  LEFT JOIN auth.users u ON u.id::TEXT = b.user_id
UNION ALL
SELECT 'app_metadata', email
  FROM auth.users
 WHERE raw_app_meta_data->>'role' IN ('admin', 'superadmin');
