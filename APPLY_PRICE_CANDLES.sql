-- ==============================================================================
-- MIGRATION: 20261008000100_price_candles.sql
--
-- Broker-side 1-minute candles built from the prices users actually trade on.
--
-- Every rpc_publish_quotes call (gold/silver every 3 s via fx-price-sweep
-- ?scope=live, the rest every minute) now also folds each mid price into
-- public.price_candles_1m (open = first, high/low = extremes, close = last).
-- The app draws M1..M30 charts for spot metals from these candles instead of
-- the thinly traded PAXG token, so candles have real bodies and wicks and
-- match the execution feed exactly - the way MT4/MT5 brokers chart their own
-- quotes. Older history still comes from the proxy series.
--
--   rpc_get_price_candles(symbol, limit)  -> newest `limit` 1-minute candles
--   rows older than 7 days are pruned automatically.
--
-- Idempotent.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.price_candles_1m (
    symbol  VARCHAR(20) NOT NULL,
    bucket  TIMESTAMPTZ NOT NULL,          -- start of the minute (UTC)
    open    NUMERIC(24, 10) NOT NULL,
    high    NUMERIC(24, 10) NOT NULL,
    low     NUMERIC(24, 10) NOT NULL,
    close   NUMERIC(24, 10) NOT NULL,
    ticks   INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (symbol, bucket)
);
ALTER TABLE public.price_candles_1m ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.price_candles_1m FROM PUBLIC, anon, authenticated;

-- Same as 20261001000100_trading_rpcs.sql plus the candle fold.
CREATE OR REPLACE FUNCTION public.rpc_publish_quotes(p_quotes JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sym    TEXT;
    v_row    JSONB;
    v_count  INTEGER := 0;
    v_bid    NUMERIC;
    v_ask    NUMERIC;
    v_mid    NUMERIC;
    v_bucket TIMESTAMPTZ := date_trunc('minute', NOW());
BEGIN
    PERFORM public.fx_require_admin();

    FOR v_sym, v_row IN SELECT key, value FROM jsonb_each(COALESCE(p_quotes, '{}'::JSONB)) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.instruments WHERE symbol = v_sym) THEN
            CONTINUE; -- ignore symbols the broker does not offer
        END IF;
        IF (v_row ->> 'bid') IS NULL OR (v_row ->> 'ask') IS NULL THEN CONTINUE; END IF;
        v_bid := (v_row ->> 'bid')::NUMERIC;
        v_ask := (v_row ->> 'ask')::NUMERIC;
        IF v_bid <= 0 OR v_ask < v_bid THEN
            CONTINUE;
        END IF;

        INSERT INTO public.market_quotes (symbol, bid, ask, quote_to_usd, source, updated_at)
        VALUES (
            v_sym, v_bid, v_ask,
            GREATEST(COALESCE((v_row ->> 'rate')::NUMERIC, 1), 0.0000000001),
            'publisher',
            NOW()
        )
        ON CONFLICT (symbol) DO UPDATE
            SET bid = EXCLUDED.bid, ask = EXCLUDED.ask,
                quote_to_usd = EXCLUDED.quote_to_usd,
                source = 'publisher', updated_at = NOW();

        -- 1-minute candle of the mid (the dealer spread is symmetric around it).
        v_mid := (v_bid + v_ask) / 2;
        INSERT INTO public.price_candles_1m (symbol, bucket, open, high, low, close, ticks)
        VALUES (v_sym, v_bucket, v_mid, v_mid, v_mid, v_mid, 1)
        ON CONFLICT (symbol, bucket) DO UPDATE
            SET high  = GREATEST(price_candles_1m.high, EXCLUDED.high),
                low   = LEAST(price_candles_1m.low, EXCLUDED.low),
                close = EXCLUDED.close,
                ticks = price_candles_1m.ticks + 1;

        v_count := v_count + 1;
    END LOOP;

    -- Keep a week of minute candles (pruned on roughly one call in a hundred).
    IF random() < 0.01 THEN
        DELETE FROM public.price_candles_1m WHERE bucket < NOW() - INTERVAL '7 days';
    END IF;

    RETURN jsonb_build_object('status', 'success', 'published', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_publish_quotes(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_publish_quotes(JSONB) TO service_role;

-- Newest p_limit minute candles of a symbol, oldest first. Signed-in users only.
CREATE OR REPLACE FUNCTION public.rpc_get_price_candles(p_symbol TEXT, p_limit INTEGER DEFAULT 1000)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               't', extract(epoch FROM c.bucket)::BIGINT,
               'o', c.open, 'h', c.high, 'l', c.low, 'c', c.close, 'n', c.ticks)
             ORDER BY c.bucket), '[]'::JSONB)
    FROM (
        SELECT * FROM public.price_candles_1m
        WHERE symbol = p_symbol
        ORDER BY bucket DESC
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 3000)
    ) c;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_price_candles(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_price_candles(TEXT, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';
