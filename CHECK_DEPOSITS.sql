-- READ-ONLY: last 10 deposits, which address each got, and the auto-verify state.
-- Safe to run in the Supabase SQL Editor (changes nothing).
SELECT
    to_char(d.created_at AT TIME ZONE 'Asia/Karachi', 'YYYY-MM-DD HH24:MI') AS created_pk,
    d.amount_claimed,
    CASE WHEN a.auto_verify THEN 'B (automatic)' ELSE 'A (manual)' END   AS address_type,
    d.address_used,
    d.status,
    d.verification_status,       -- WAITING = checking blockchain every minute
    d.verification_error,        -- e.g. TIMEOUT = no payment found in 30 min
    d.verification_attempts,
    d.proof_path IS NOT NULL      AS has_screenshot
FROM public.deposit_requests d
LEFT JOIN public.company_deposit_addresses a ON a.address = d.address_used
ORDER BY d.created_at DESC
LIMIT 10;

-- Is the every-minute checker running? (last 5 runs)
SELECT status, return_message, start_time
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'auto-verify-deposits')
ORDER BY start_time DESC
LIMIT 5;
