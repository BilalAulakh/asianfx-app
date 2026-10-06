-- ==============================================================================
-- MIGRATION: 20261002000400_engine_correctness.sql
--
-- Engine correctness fixes:
--
--  1. STOP-LOSS GAP FILL. A triggered stop loss was settled AT the stop level
--     even when the market had gapped straight through it (weekend open, news),
--     handing the client a price that never traded. A stop loss is a stop
--     order: once triggered it fills at the current executable price (bid for a
--     long, ask for a short), never better than the stop level. Pending STOP
--     entry orders already filled at the current bid/ask; that is kept.
--     Take profit still fills at its level.
--
--  2. NO EXECUTION ON STALE PRICES. Triggers, SL/TP and stop-out now act only
--     on a fresh `publisher` quote. A symbol whose feed is down / market is
--     closed is left untouched until a live price returns.
--
--  3. FAIR SWEEP. rpc_sweep_accounts took `LIMIT 500` of an unordered DISTINCT,
--     so beyond 500 exposed accounts some could be starved forever. Accounts
--     are now processed least-recently-evaluated first (account_sweep_state).
--
--  4. SWAP. Swap was charged per 24h since open, regardless of the clock, so a
--     position opened 10 minutes before rollover and held over it paid nothing,
--     and weekends were never tripled. It is now charged per ROLLOVER crossed at
--     broker_config.rollover_hour_utc (default 21:00 UTC):
--       forex & metals : Mon-Fri, Wednesday counts x3 (covers the weekend)
--       crypto         : every day x1
--       everything else: Mon-Fri x1
--
--  5. broker_config.require_kyc_for_trading = TRUE.
-- ==============================================================================

ALTER TABLE public.broker_config ADD COLUMN IF NOT EXISTS rollover_hour_utc SMALLINT NOT NULL DEFAULT 21;
ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_rollover_hour_utc_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_rollover_hour_utc_check
    CHECK (rollover_hour_utc BETWEEN 0 AND 23);

UPDATE public.broker_config
   SET require_kyc_for_trading = TRUE,
       updated_at = NOW()
 WHERE id = 1;

ALTER TABLE public.broker_config ALTER COLUMN require_kyc_for_trading SET DEFAULT TRUE;

-- ------------------------------------------------------------------------------
-- Sweep bookkeeping (kept off `wallets` so it does not spam realtime clients).
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_sweep_state (
    user_id           TEXT PRIMARY KEY,
    last_evaluated_at TIMESTAMPTZ,
    last_error        TEXT,
    error_count       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_account_sweep_state_last
    ON public.account_sweep_state (last_evaluated_at NULLS FIRST);

ALTER TABLE public.account_sweep_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_sweep_state FROM anon, authenticated;

-- ------------------------------------------------------------------------------
-- 4. ROLLOVER COUNTING
-- Number of (weighted) rollovers strictly after p_from and up to p_to.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_swap_rollover_count(
    p_from     TIMESTAMPTZ,
    p_to       TIMESTAMPTZ,
    p_category TEXT,
    p_hour     INTEGER DEFAULT 21
)
RETURNS INTEGER
LANGUAGE sql STABLE
SET search_path = public
AS $$
    SELECT COALESCE(SUM(
               CASE
                   WHEN lower(p_category) = 'crypto'                 THEN 1
                   WHEN EXTRACT(ISODOW FROM r) IN (6, 7)             THEN 0
                   WHEN lower(p_category) IN ('forex', 'metals')
                        AND EXTRACT(ISODOW FROM r) = 3               THEN 3
                   ELSE 1
               END), 0)::INTEGER
    FROM generate_series(
             date_trunc('day', p_from AT TIME ZONE 'UTC') + make_interval(hours => GREATEST(LEAST(p_hour, 23), 0)),
             p_to AT TIME ZONE 'UTC',
             INTERVAL '1 day') AS r
    WHERE p_from IS NOT NULL
      AND p_to IS NOT NULL
      AND r >  p_from AT TIME ZONE 'UTC'
      AND r <= p_to   AT TIME ZONE 'UTC';
$$;

-- ------------------------------------------------------------------------------
-- ATOMIC CLOSE PRIMITIVE — identical to 20261001000100 except for the swap.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_close_trade_row(
    p_trade_id     TEXT,
    p_close_price  NUMERIC,
    p_close_bid    NUMERIC,
    p_close_ask    NUMERIC,
    p_rate         NUMERIC,
    p_reason       TEXT,
    p_price_source TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_t        public.trades;
    v_inst     public.instruments;
    v_cfg      public.broker_config;
    v_wallet   public.wallets;
    v_pnl      NUMERIC;
    v_swap     NUMERIC := 0;
    v_rolls    INTEGER := 0;
    v_release  NUMERIC;
    v_new_bal  NUMERIC;
    v_status   TEXT;
BEGIN
    SELECT * INTO v_t FROM public.trades
    WHERE id = p_trade_id AND status = 'open'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'already_closed', 'trade_id', p_trade_id);
    END IF;

    IF p_close_price IS NULL OR p_close_price <= 0 THEN
        RAISE EXCEPTION 'NO_QUOTE: cannot close % without an authoritative price', p_trade_id
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_inst FROM public.instruments WHERE symbol = v_t.symbol;
    SELECT * INTO v_cfg  FROM public.broker_config WHERE id = 1;

    -- Swap: weighted rollovers crossed * lots * per-lot rate for the side.
    IF v_inst.symbol IS NOT NULL THEN
        v_rolls := public.fx_swap_rollover_count(
            COALESCE(v_t.filled_at, v_t.open_time), NOW(), v_inst.category,
            COALESCE(v_cfg.rollover_hour_utc, 21));
        v_swap := ROUND(
            v_rolls * v_t.lots *
            CASE WHEN v_t.side = 'buy' THEN v_inst.swap_long_per_lot ELSE v_inst.swap_short_per_lot END,
            4);
    END IF;

    v_pnl := public.fx_calc_pnl(
        v_t.side, v_t.open_price, p_close_price, v_t.lots, v_t.contract_size,
        COALESCE(p_rate, v_t.quote_to_usd_rate));

    SELECT * INTO v_wallet FROM public.wallets
    WHERE user_id = v_t.user_id AND currency = 'USD' FOR UPDATE;

    v_release := LEAST(COALESCE(v_t.required_margin, 0), COALESCE(v_wallet.held_margin, 0));
    v_new_bal := COALESCE(v_wallet.balance, 0) + v_pnl - v_swap;

    UPDATE public.wallets
       SET held_margin = held_margin - v_release,
           balance     = v_new_bal,
           updated_at  = NOW()
     WHERE user_id = v_t.user_id AND currency = 'USD';

    v_status := CASE WHEN p_reason = 'STOP_OUT' THEN 'liquidated' ELSE 'closed' END;

    UPDATE public.trades
       SET status         = v_status,
           close_price    = p_close_price,
           current_price  = p_close_price,
           close_bid      = p_close_bid,
           close_ask      = p_close_ask,
           realized_pnl   = v_pnl,
           swap           = v_swap,
           unrealized_pnl = 0,
           close_time     = NOW(),
           close_reason   = p_reason,
           price_source   = COALESCE(p_price_source, v_t.price_source),
           updated_at     = NOW()
     WHERE id = p_trade_id;

    PERFORM public.fx_post_ledger(
        v_t.user_id, 'margin_release', v_release, v_new_bal, p_trade_id,
        format('Margin released for %s (%s)', v_t.symbol, p_reason),
        'margin_release:' || p_trade_id);

    IF v_pnl <> 0 THEN
        PERFORM public.fx_post_ledger(
            v_t.user_id,
            CASE WHEN v_pnl > 0 THEN 'realized_profit' ELSE 'realized_loss' END,
            v_pnl, v_new_bal, p_trade_id,
            format('Realized PnL on %s @ %s (%s)', v_t.symbol, p_close_price, p_reason),
            'realized_pnl:' || p_trade_id);
    END IF;

    IF v_swap <> 0 THEN
        PERFORM public.fx_post_ledger(
            v_t.user_id, 'swap', -v_swap, v_new_bal, p_trade_id,
            format('Swap on %s for %s rollover(s)', v_t.symbol, v_rolls),
            'swap:' || p_trade_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'trade_id', p_trade_id,
        'symbol', v_t.symbol,
        'side', v_t.side,
        'lots', v_t.lots,
        'open_price', v_t.open_price,
        'close_price', p_close_price,
        'realized_pnl', v_pnl,
        'swap', v_swap,
        'rollovers', v_rolls,
        'commission', v_t.commission,
        'released_margin', v_release,
        'close_reason', p_reason,
        'trade_status', v_status,
        'new_balance', v_new_bal
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- RISK EVALUATION ENGINE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_evaluate_account(p_user_id TEXT, p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cfg       public.broker_config;
    v_row       RECORD;
    v_q         public.fx_quote_t;
    v_hit       BOOLEAN;
    v_fill      NUMERIC;
    v_reason    TEXT;
    v_res       JSONB;
    v_triggered JSONB := '[]'::JSONB;
    v_closed    JSONB := '[]'::JSONB;
    v_expired   INTEGER := 0;
    v_passes    INTEGER := 0;
    v_snap      JSONB;
    v_level     NUMERIC;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;

    PERFORM public.fx_lock_wallet(p_user_id);

    -- ---- Expire resting orders that outlived their validity.
    UPDATE public.trades
       SET status = 'expired', close_reason = 'EXPIRED', updated_at = NOW()
     WHERE user_id = p_user_id AND status = 'pending'
       AND expires_at IS NOT NULL AND expires_at <= NOW();
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    -- ---- Trigger pending limit / stop orders, on a LIVE price only.
    --      Both fill at the current executable price (a stop through a gap fills
    --      at the post-gap price; a limit fills at its level or better).
    FOR v_row IN
        SELECT id, side, type, target_price, symbol
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'pending'
        ORDER BY created_at
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL OR v_q.source <> 'publisher' OR v_row.target_price IS NULL;

        v_hit := CASE
            WHEN v_row.type = 'limit' AND v_row.side = 'buy'  THEN v_q.ask <= v_row.target_price
            WHEN v_row.type = 'limit' AND v_row.side = 'sell' THEN v_q.bid >= v_row.target_price
            WHEN v_row.type = 'stop'  AND v_row.side = 'buy'  THEN v_q.ask >= v_row.target_price
            WHEN v_row.type = 'stop'  AND v_row.side = 'sell' THEN v_q.bid <= v_row.target_price
            ELSE FALSE
        END;

        IF v_hit THEN
            v_fill := CASE WHEN v_row.side = 'buy' THEN v_q.ask ELSE v_q.bid END;
            v_res  := public.fx_activate_trade(
                v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, v_q.source);
            v_triggered := v_triggered || v_res;
        END IF;
    END LOOP;

    -- ---- Stop loss / take profit on a LIVE price. Risk is checked before reward.
    FOR v_row IN
        SELECT id, side, symbol, stop_loss, take_profit
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'open'
          AND (stop_loss IS NOT NULL OR take_profit IS NOT NULL)
        ORDER BY open_time
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL OR v_q.source <> 'publisher';

        v_reason := NULL;
        IF v_row.side = 'buy' THEN
            IF v_row.stop_loss IS NOT NULL AND v_q.bid <= v_row.stop_loss THEN
                -- Gap fill: the bid, which is at or below the stop.
                v_reason := 'STOP_LOSS'; v_fill := LEAST(v_q.bid, v_row.stop_loss);
            ELSIF v_row.take_profit IS NOT NULL AND v_q.bid >= v_row.take_profit THEN
                v_reason := 'TAKE_PROFIT'; v_fill := v_row.take_profit;
            END IF;
        ELSE
            IF v_row.stop_loss IS NOT NULL AND v_q.ask >= v_row.stop_loss THEN
                -- Gap fill: the ask, which is at or above the stop.
                v_reason := 'STOP_LOSS'; v_fill := GREATEST(v_q.ask, v_row.stop_loss);
            ELSIF v_row.take_profit IS NOT NULL AND v_q.ask <= v_row.take_profit THEN
                v_reason := 'TAKE_PROFIT'; v_fill := v_row.take_profit;
            END IF;
        END IF;

        IF v_reason IS NOT NULL THEN
            v_res := public.fx_close_trade_row(
                v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, v_reason, v_q.source);
            IF (v_res ->> 'status') = 'success' THEN
                v_closed := v_closed || v_res;
            END IF;
        END IF;
    END LOOP;

    -- ---- Stop-out: liquidate the worst LIVE-priced loser, recompute, repeat.
    LOOP
        v_snap  := public.fx_account_snapshot(p_user_id, NULL);
        v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

        EXIT WHEN v_level IS NULL;
        EXIT WHEN v_level > v_cfg.stop_out_level_pct;
        EXIT WHEN (v_snap ->> 'open_positions')::INTEGER = 0;
        EXIT WHEN v_passes >= v_cfg.max_liquidation_passes;

        SELECT t.id, t.side, t.symbol INTO v_row
        FROM public.trades t
        CROSS JOIN LATERAL public.fx_resolve_quote(t.symbol, NULL, FALSE, FALSE) q
        WHERE t.user_id = p_user_id AND t.status = 'open'
          AND q.source = 'publisher'
        ORDER BY public.fx_calc_pnl(
                    t.side, t.open_price,
                    CASE WHEN t.side = 'buy' THEN q.bid ELSE q.ask END,
                    t.lots, t.contract_size, q.quote_to_usd) ASC
        LIMIT 1;
        EXIT WHEN NOT FOUND;

        v_q := public.fx_resolve_quote(v_row.symbol, NULL, FALSE, FALSE);
        EXIT WHEN v_q.source <> 'publisher';
        v_fill := CASE WHEN v_row.side = 'buy' THEN v_q.bid ELSE v_q.ask END;
        EXIT WHEN v_fill IS NULL;

        v_res := public.fx_close_trade_row(
            v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, 'STOP_OUT', v_q.source);
        EXIT WHEN (v_res ->> 'status') <> 'success';

        v_closed := v_closed || v_res;
        v_passes := v_passes + 1;
    END LOOP;

    v_snap  := public.fx_account_snapshot(p_user_id, NULL);
    v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

    INSERT INTO public.account_sweep_state (user_id, last_evaluated_at, last_error)
    VALUES (p_user_id, NOW(), NULL)
    ON CONFLICT (user_id) DO UPDATE
        SET last_evaluated_at = EXCLUDED.last_evaluated_at, last_error = NULL;

    RETURN jsonb_build_object(
        'status', 'success',
        'triggered', v_triggered,
        'closed', v_closed,
        'expired', v_expired,
        'liquidations', v_passes,
        'margin_call', COALESCE(v_level < v_cfg.margin_call_level_pct, FALSE),
        'stop_out', COALESCE(v_level <= v_cfg.stop_out_level_pct, FALSE),
        'account', v_snap);
END;
$$;

-- ------------------------------------------------------------------------------
-- FAIR OFFLINE SWEEP — least recently evaluated accounts first.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_sweep_accounts(p_max_accounts INTEGER DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid       TEXT;
    v_res       JSONB;
    v_exposed   INTEGER := 0;
    v_accounts  INTEGER := 0;
    v_closed    INTEGER := 0;
    v_triggered INTEGER := 0;
    v_errors    INTEGER := 0;
BEGIN
    PERFORM public.fx_require_admin();

    SELECT COUNT(DISTINCT user_id) INTO v_exposed
    FROM public.trades WHERE status IN ('open', 'pending');

    FOR v_uid IN
        SELECT a.user_id
        FROM (SELECT DISTINCT user_id FROM public.trades WHERE status IN ('open', 'pending')) a
        LEFT JOIN public.account_sweep_state s ON s.user_id = a.user_id
        ORDER BY s.last_evaluated_at ASC NULLS FIRST, a.user_id
        LIMIT GREATEST(COALESCE(p_max_accounts, 500), 1)
    LOOP
        BEGIN
            v_res := public.fx_evaluate_account(v_uid, NULL);
            v_accounts  := v_accounts + 1;
            v_closed    := v_closed + jsonb_array_length(v_res -> 'closed');
            v_triggered := v_triggered + jsonb_array_length(v_res -> 'triggered');
        EXCEPTION WHEN OTHERS THEN
            -- One bad account must neither abort the sweep nor starve the queue.
            v_errors := v_errors + 1;
            INSERT INTO public.account_sweep_state (user_id, last_evaluated_at, last_error, error_count)
            VALUES (v_uid, NOW(), LEFT(SQLERRM, 500), 1)
            ON CONFLICT (user_id) DO UPDATE
                SET last_evaluated_at = NOW(),
                    last_error        = EXCLUDED.last_error,
                    error_count       = public.account_sweep_state.error_count + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'accounts_with_exposure', v_exposed,
        'accounts_evaluated', v_accounts,
        'positions_closed', v_closed,
        'orders_triggered', v_triggered,
        'errors', v_errors,
        'swept_at', NOW());
END;
$$;

-- ------------------------------------------------------------------------------
-- GRANTS (re-asserted; internal primitives stay unreachable from clients)
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fx_close_trade_row(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_evaluate_account(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_sweep_accounts(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_accounts(INTEGER) TO service_role;

-- ------------------------------------------------------------------------------
-- DEPLOYED-VERSION MARKER (no longer reveals the admin head-count to anon).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_engine_version()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'engine', '2026-10-02.1',
        'uuid_source', 'gen_random_uuid',
        'kyc_module', public.fx_kyc_module_installed(),
        'manual_deposits', to_regclass('public.deposit_requests') IS NOT NULL,
        'client_quotes', (SELECT allow_client_quotes FROM public.broker_config WHERE id = 1),
        'require_kyc_for_trading', (SELECT require_kyc_for_trading FROM public.broker_config WHERE id = 1),
        'instruments', (SELECT COUNT(*) FROM public.instruments)
    );
$$;

GRANT EXECUTE ON FUNCTION public.fx_engine_version() TO authenticated, anon, service_role;
