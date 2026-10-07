-- ==============================================================================
-- MIGRATION: 20261008000000_per_instrument_quote_age.sql
--
-- Per-instrument freshness limit for execution prices.
--
-- instruments.max_quote_age_seconds (NULL = broker_config.quote_max_age_seconds)
-- lets live-fed instruments refuse old prices much sooner than the rest:
--   XAU/USD XAG/USD XPT/USD   12 s   (published every 3 s by fx-price-sweep ?scope=live)
--   EUR/USD GBP/USD USD/JPY   45 s   (every 30 s by the live job, every minute by the full run)
--   everything else           broker default (60 s)
-- A trade can therefore never be opened or closed on a gold price more than
-- 12 seconds old: that closes the "stale price" arbitrage on a B-book.
--
-- fx_resolve_quote() is unchanged apart from the freshness test.
--
-- APPLY ONLY AFTER the live job runs (SCHEDULE_PRICE_LIVE.sql), otherwise gold
-- (updated once a minute without it) would answer NO_QUOTE most of the time.
-- To undo: UPDATE public.instruments SET max_quote_age_seconds = NULL;
-- Idempotent.
-- ==============================================================================

ALTER TABLE public.instruments ADD COLUMN IF NOT EXISTS max_quote_age_seconds INTEGER;
ALTER TABLE public.instruments DROP CONSTRAINT IF EXISTS instruments_max_quote_age_check;
ALTER TABLE public.instruments ADD CONSTRAINT instruments_max_quote_age_check
    CHECK (max_quote_age_seconds IS NULL OR max_quote_age_seconds BETWEEN 3 AND 3600);

CREATE OR REPLACE FUNCTION public.fx_resolve_quote(
    p_symbol  TEXT,
    p_quotes  JSONB   DEFAULT NULL,
    p_persist BOOLEAN DEFAULT TRUE,
    p_strict  BOOLEAN DEFAULT TRUE
)
RETURNS public.fx_quote_t
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_cfg     public.broker_config;
    v_mq      public.market_quotes;
    v_max_age INTEGER;
    v_fresh   BOOLEAN;
    v_in      JSONB;
    v_bid     NUMERIC;
    v_ask     NUMERIC;
    v_ref     NUMERIC;
    v_out     public.fx_quote_t;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    SELECT * INTO v_mq  FROM public.market_quotes WHERE symbol = p_symbol;
    SELECT COALESCE(i.max_quote_age_seconds, v_cfg.quote_max_age_seconds) INTO v_max_age
    FROM public.instruments i WHERE i.symbol = p_symbol;
    v_max_age := COALESCE(v_max_age, v_cfg.quote_max_age_seconds);

    v_fresh := v_mq.symbol IS NOT NULL
           AND v_mq.source = 'publisher'
           AND v_mq.updated_at > NOW() - make_interval(secs => v_max_age);

    -- ---- Optional client quote: a stale-screen guard, never a price source.
    IF v_cfg.allow_client_quotes AND p_quotes IS NOT NULL THEN
        v_in := p_quotes -> p_symbol;
    END IF;

    IF v_in IS NOT NULL AND jsonb_typeof(v_in) = 'object' THEN
        IF NOT v_fresh THEN
            IF p_strict THEN
                RAISE EXCEPTION 'NO_QUOTE: no live server price for % (market closed or price feed offline); client prices are not accepted without one', p_symbol
                    USING ERRCODE = '22023';
            END IF;
        ELSE
            BEGIN
                v_bid := (v_in ->> 'bid')::NUMERIC;
                v_ask := (v_in ->> 'ask')::NUMERIC;
            EXCEPTION WHEN OTHERS THEN
                v_bid := NULL;
                v_ask := NULL;
            END;

            IF v_bid IS NULL OR v_ask IS NULL OR v_bid <= 0 OR v_ask < v_bid THEN
                IF p_strict THEN
                    RAISE EXCEPTION 'BAD_QUOTE: % submitted an invalid bid/ask', p_symbol
                        USING ERRCODE = '22023';
                END IF;
            ELSE
                v_ref := (v_mq.bid + v_mq.ask) / 2;
                IF v_ref > 0
                   AND ABS(((v_bid + v_ask) / 2) - v_ref) / v_ref > v_cfg.quote_band_fraction
                   AND p_strict
                THEN
                    RAISE EXCEPTION
                        'QUOTE_OUT_OF_BAND: the price on screen for % (mid %) is more than % pct away from the live price (mid %); refresh and try again',
                        p_symbol, ROUND((v_bid + v_ask) / 2, 8), (v_cfg.quote_band_fraction * 100), ROUND(v_ref, 8)
                        USING ERRCODE = '22023';
                END IF;
            END IF;
        END IF;
    END IF;

    -- ---- 1. Fresh publisher quote: the only execution price.
    IF v_fresh THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'publisher', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    -- ---- 2. No fresh price.
    IF p_strict THEN
        RAISE EXCEPTION 'NO_QUOTE: no live price for % right now (market closed or price feed offline)', p_symbol
            USING ERRCODE = '22023';
    END IF;

    IF v_mq.symbol IS NOT NULL THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'stale', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    v_out := ROW(p_symbol, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC, 'none', NULL::TIMESTAMPTZ)::public.fx_quote_t;
    RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.fx_resolve_quote(TEXT, JSONB, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;

UPDATE public.instruments SET max_quote_age_seconds = 12 WHERE symbol IN ('XAU/USD', 'XAG/USD', 'XPT/USD');
UPDATE public.instruments SET max_quote_age_seconds = 45 WHERE symbol IN ('EUR/USD', 'GBP/USD', 'USD/JPY');

SELECT symbol, max_quote_age_seconds FROM public.instruments
WHERE max_quote_age_seconds IS NOT NULL ORDER BY symbol;
