-- ==============================================================================
-- MIGRATION: 20261007000300_address_b_no_auto_limit.sql
--
-- Address B (automatic) credits any verified on-chain USDT transfer, whatever
-- the amount: its max_auto_approve_usd is raised to the column's maximum, so
-- rpc_system_approve_deposit no longer hands large deposits to an admin as
-- ABOVE_AUTO_LIMIT. Every other check is unchanged (confirmed on-chain, real
-- USDT contract, paid to B, TXID used once, sent after the request).
--
-- Note: re-running 20261006000100_auto_verify_deposits.sql would reset the
-- limit to 1000; run this file again afterwards. Idempotent.
-- ==============================================================================

UPDATE public.company_deposit_addresses
   SET max_auto_approve_usd = 99999999999999.9999,   -- NUMERIC(18,4) maximum = no limit
       updated_at = NOW()
 WHERE auto_verify;

-- Requests already handed to an admin because of the old limit stay in the
-- admin Pending queue (badge "Auto-verify failed: above auto limit", TXID and
-- on-chain amount filled in) for a one-click manual approval: their TXID is
-- already recorded, so the verifier would not re-match it.

SELECT address, label, auto_verify, max_auto_approve_usd
FROM public.company_deposit_addresses
WHERE auto_verify;
