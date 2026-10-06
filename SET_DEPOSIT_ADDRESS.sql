-- ##############################################################################
--  SET_DEPOSIT_ADDRESS.sql  —  paste into the Supabase SQL Editor and Run.
--
--  Fixes "deposits are not configured yet" on CONFIRM DEPOSIT:
--  rpc_submit_deposit_request refuses every claim while
--  broker_config.deposit_address_trc20 is NULL. This sets it to the same
--  address the app shows (AppConstants.usdtTrc20DepositAddress).
--  Safe to run more than once.
-- ##############################################################################

UPDATE public.broker_config
   SET deposit_address_trc20 = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV',
       updated_at = NOW()
 WHERE id = 1;

-- Check: should return one row with the address above.
SELECT id, deposit_address_trc20, min_deposit_usd
  FROM public.broker_config
 WHERE id = 1;
