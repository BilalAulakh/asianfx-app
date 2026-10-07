-- ==============================================================================
-- Broker fees: below Exness Standard on metals, plus a small commission.
--
--   Spread (every trade, built into the BUY/SELL price):
--     XAU/USD  18 points = $0.18 / oz -> $18 per lot   (Exness Standard ~20-35)
--     XAG/USD   2 points = $0.02 / oz -> $100 per lot
--     other instruments: unchanged (Admin > Dealing Desk)
--   Commission: $2 per lot, ALL instruments, charged once when a trade opens
--     (0.01 lot = $0.02, 0.10 lot = $0.20, 1 lot = $2). Shown in the order
--     screen of app 1.0.14+ and as "Commission" in the account statement.
--   Swap: 0 on every instrument (swap-free / Islamic-friendly).
--   No deposit or withdrawal fees.
--
-- Takes effect within a minute (next price sweep), for every user, no app
-- update needed. Change later in Admin > Dealing Desk (spread) or by running
-- this file again with other numbers. Safe to run again.
-- ==============================================================================

UPDATE public.instruments SET spread_markup_points = 18, updated_at = NOW() WHERE symbol = 'XAU/USD';
UPDATE public.instruments SET spread_markup_points = 2,  updated_at = NOW() WHERE symbol = 'XAG/USD';

UPDATE public.instruments
   SET commission_per_lot = 2,
       swap_long_per_lot  = 0,
       swap_short_per_lot = 0,
       updated_at = NOW();

-- What a 1-lot trade costs on gold and silver now (multiplier must be 1).
SELECT i.symbol,
       i.spread_markup_points                                                       AS spread_points,
       c.spread_multiplier                                                          AS multiplier,
       ROUND(i.spread_markup_points * c.spread_multiplier) * i.point_size * i.contract_size AS spread_usd_per_lot,
       i.commission_per_lot                                                         AS commission_usd_per_lot,
       ROUND(i.spread_markup_points * c.spread_multiplier) * i.point_size * i.contract_size
         + i.commission_per_lot                                                     AS total_usd_per_lot
FROM public.instruments i
CROSS JOIN public.broker_config c
WHERE c.id = 1 AND i.symbol IN ('XAU/USD', 'XAG/USD')
ORDER BY i.symbol;
