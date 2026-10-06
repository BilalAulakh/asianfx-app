-- ==============================================================================
-- Gold / silver spreads in line with retail brokers (e.g. Exness Standard:
-- XAUUSD ~20-35 points, XAGUSD ~2-3 cents).
--
-- The price publisher (fx-price-sweep) quotes:
--   spread = spread_markup_points x broker_config.spread_multiplier x point
--   point  = 10^-digits   (XAU/USD and XAG/USD have 2 digits -> 0.01)
--
--   XAU/USD  25 points -> $0.25 per oz -> $25 per lot (100 oz)
--   XAG/USD   3 points -> $0.03 per oz -> $150 per lot (5000 oz)
--
-- The broker keeps this spread on every trade (B-book). Takes effect on the
-- next price sweep (within a minute). Change later in Admin > Dealing Desk.
-- Safe to run again.
-- ==============================================================================

UPDATE public.instruments SET spread_markup_points = 25, updated_at = NOW() WHERE symbol = 'XAU/USD';
UPDATE public.instruments SET spread_markup_points = 3,  updated_at = NOW() WHERE symbol = 'XAG/USD';

-- Result: the spread users will see. multiplier must be 1 for the values above
-- (if it is 2, every spread is doubled).
SELECT i.symbol,
       i.spread_markup_points                                   AS markup_points,
       c.spread_multiplier                                      AS multiplier,
       ROUND(i.spread_markup_points * c.spread_multiplier) * i.point_size AS spread_price,
       ROUND(i.spread_markup_points * c.spread_multiplier) * i.point_size * i.contract_size AS broker_earns_per_lot_usd
FROM public.instruments i
CROSS JOIN public.broker_config c
WHERE c.id = 1 AND i.symbol IN ('XAU/USD', 'XAG/USD')
ORDER BY i.symbol;
