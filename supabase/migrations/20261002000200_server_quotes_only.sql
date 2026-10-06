-- ==============================================================================
-- MIGRATION: 20261002000200_server_quotes_only.sql
--
-- CLIENT-SUBMITTED PRICES.
--
-- fx_resolve_quote() let the app hand in its own bid/ask (p_quotes). When no
-- fresh publisher quote existed it accepted any client price within 2% of the
-- LAST STORED price — and then persisted it as the new reference. A client
-- could therefore walk the reference 2% per call, fill at a price of its
-- choosing, and supply its own quote->USD conversion `rate` as well.
--
-- New rules:
--   * Execution prices come ONLY from a fresh `publisher` quote (written by the
--     fx-price-sweep Edge Function with the service key).
--   * A client quote is never persisted and never used as a fill price. If
--     client quotes are ever re-enabled, the client's view is only band-checked
--     against the fresh publisher price (a stale-screen guard) and its `rate`
--     is ignored; with no fresh publisher price it is rejected outright.
--   * Strict callers (rpc_open_trade, rpc_close_trade) fail with NO_QUOTE when
--     there is no fresh publisher price (feed down or market closed).
--   * Non-strict callers (account snapshots, the risk sweep) may still SEE the
--     last stored price, labelled source='stale'. The engine no longer EXECUTES
--     on stale prices (see 20261002000400_engine_correctness.sql).
-- ==============================================================================

UPDATE public.broker_config
   SET allow_client_quotes = FALSE,
       quote_band_fraction = 0.003,
       updated_at          = NOW()
 WHERE id = 1;

ALTER TABLE public.broker_config ALTER COLUMN allow_client_quotes SET DEFAULT FALSE;
ALTER TABLE public.broker_config ALTER COLUMN quote_band_fraction SET DEFAULT 0.003;

-- Same signature as before so every existing caller keeps compiling.
-- p_persist is accepted for compatibility and ignored: nothing a client sends
-- is ever written to market_quotes.
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
    v_cfg   public.broker_config;
    v_mq    public.market_quotes;
    v_fresh BOOLEAN;
    v_in    JSONB;
    v_bid   NUMERIC;
    v_ask   NUMERIC;
    v_ref   NUMERIC;
    v_out   public.fx_quote_t;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    SELECT * INTO v_mq  FROM public.market_quotes WHERE symbol = p_symbol;

    v_fresh := v_mq.symbol IS NOT NULL
           AND v_mq.source = 'publisher'
           AND v_mq.updated_at > NOW() - make_interval(secs => v_cfg.quote_max_age_seconds);

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
            -- Non-strict: ignore the client quote entirely.
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
            -- 'rate' from the client is ignored by construction: the fill below
            -- always carries the publisher's own conversion rate.
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

-- rpc_sync_account used to pre-persist client quotes before evaluating. That
-- step is gone; p_quotes is accepted for compatibility and ignored.
CREATE OR REPLACE FUNCTION public.rpc_sync_account(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    RETURN public.fx_evaluate_account(v_uid, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_sync_account(JSONB) TO authenticated;

-- rpc_get_account_state: likewise ignore client quotes for the snapshot.
CREATE OR REPLACE FUNCTION public.rpc_get_account_state(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    RETURN public.fx_account_snapshot(v_uid, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_account_state(JSONB) TO authenticated;
