-- ##############################################################################
--  CHECK_PRICES.sql  —  read-only diagnostic. Paste into the Supabase SQL Editor
--  and Run. Changes nothing. Shows whether the price jobs are scheduled and
--  running, and how fresh gold's published price is.
-- ##############################################################################

-- 1. Scheduled jobs (expect fx-price-sweep '* * * * *', fx-price-sweep-metals
--    '10 seconds', auto-verify-deposits '* * * * *', all active = true).
SELECT jobname, schedule, active FROM cron.job ORDER BY jobname;

-- 2. Last runs of the price jobs (status should be 'succeeded', start_time recent).
SELECT j.jobname, d.status, d.start_time, d.return_message
  FROM cron.job_run_details d
  JOIN cron.job j ON j.jobid = d.jobid
 WHERE j.jobname LIKE 'fx-price-sweep%'
 ORDER BY d.start_time DESC
 LIMIT 10;

-- 3. Gold / silver / BTC published prices and their age in seconds
--    (should be under ~15 s for metals while the market is open).
SELECT symbol, bid, ask, source, updated_at,
       ROUND(EXTRACT(EPOCH FROM (NOW() - updated_at))) AS age_seconds
  FROM public.market_quotes
 WHERE symbol IN ('XAU/USD', 'XAG/USD', 'BTC/USD')
 ORDER BY symbol;
