-- ==============================================================================
-- MIGRATION: 20261001000200_trading_public_rpcs.sql
--
-- The client-facing trading API. Flutter may only REQUEST; these functions
-- decide, settle and return the authoritative result.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. REMOVE THE INSECURE PREDECESSORS
--    Dropping every overload by name prevents the old, vulnerable signature
--    from lingering next to the new one (PostgREST would happily call either).
-- ------------------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('rpc_open_trade', 'rpc_close_trade')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

-- ------------------------------------------------------------------------------
-- 1. OPEN A MARKET POSITION, OR PLACE A PENDING LIMIT / STOP ORDER
--
-- Validation order (all server-side — the client's numbers are only a request):
--   auth -> idempotency -> instrument -> trading enabled -> KYC -> side/type
--   -> lots (min/max/step) -> leverage (<= instrument cap) -> authoritative quote
--   -> execution price -> slippage -> pending-order side sanity -> SL/TP sides
--   -> margin -> free margin -> INSERT -> lock margin -> ledger -> commit
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_open_trade(
    p_symbol            TEXT,
    p_side              TEXT,
    p_type              TEXT          DEFAULT 'market',
    p_lots              NUMERIC       DEFAULT NULL,
    p_leverage          NUMERIC       DEFAULT NULL,
    p_target_price      NUMERIC       DEFAULT NULL,
    p_stop_loss         NUMERIC       DEFAULT NULL,
    p_take_profit       NUMERIC       DEFAULT NULL,
    p_client_request_id TEXT          DEFAULT NULL,
    p_quotes            JSONB         DEFAULT NULL,
    p_requested_price   NUMERIC       DEFAULT NULL,
    p_expires_at        TIMESTAMPTZ   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid      TEXT;
    v_cfg      public.broker_config;
    v_inst     public.instruments;
    v_q        public.fx_quote_t;
    v_wallet   public.wallets;
    v_existing public.trades;
    v_side     TEXT;
    v_type     TEXT;
    v_lots     NUMERIC;
    v_lev      NUMERIC;
    v_entry    NUMERIC;
    v_margin   NUMERIC := 0;
    v_comm     NUMERIC := 0;
    v_unreal   NUMERIC;
    v_free     NUMERIC;
    v_new_bal  NUMERIC;
    v_trade_id TEXT;
    v_order_id TEXT;
    v_kyc      TEXT;
    v_status   TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;

    -- ---- Idempotency: a retried / double-tapped request returns the first trade.
    IF p_client_request_id IS NOT NULL THEN
        SELECT * INTO v_existing FROM public.trades
        WHERE user_id = v_uid AND client_request_id = p_client_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', 'duplicate',
                'trade_id', v_existing.id,
                'order_id', v_existing.order_id,
                'trade_status', v_existing.status,
                'message', 'This order request was already processed.',
                'account', public.fx_account_snapshot(v_uid, NULL));
        END IF;
    END IF;

    -- ---- Instrument
    SELECT * INTO v_inst FROM public.instruments WHERE symbol = p_symbol;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UNKNOWN_INSTRUMENT: % is not offered by this broker', p_symbol
            USING ERRCODE = '22023';
    END IF;
    IF NOT v_inst.trading_enabled THEN
        RAISE EXCEPTION 'MARKET_CLOSED: trading in % is currently disabled', p_symbol
            USING ERRCODE = '22023';
    END IF;

    -- ---- Trading permission / KYC (server-side, not a client boolean)
    --
    -- Skipped entirely when the compliance module is not deployed: with no
    -- kyc_profiles table there is nothing for the database to check, so the
    -- app's own KycPolicy remains the only gate rather than every order being
    -- refused.
    IF public.fx_kyc_module_installed() THEN
        v_kyc := public.fx_kyc_status(v_uid);

        IF v_cfg.require_kyc_for_trading AND COALESCE(v_kyc, 'NOT_STARTED') <> 'APPROVED' THEN
            RAISE EXCEPTION 'KYC_REQUIRED: identity verification must be approved before trading'
                USING ERRCODE = '42501';
        END IF;

        IF v_kyc = 'REJECTED' THEN
            RAISE EXCEPTION 'KYC_REJECTED: trading is blocked while verification is rejected'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- ---- Side / type
    v_side := LOWER(COALESCE(p_side, ''));
    v_type := COALESCE(NULLIF(p_type, ''), 'market');
    IF v_side NOT IN ('buy', 'sell') THEN
        RAISE EXCEPTION 'BAD_SIDE: side must be buy or sell, got %', p_side USING ERRCODE = '22023';
    END IF;
    IF v_type NOT IN ('market', 'limit', 'stop') THEN
        RAISE EXCEPTION 'BAD_ORDER_TYPE: % is not a supported order type', p_type USING ERRCODE = '22023';
    END IF;

    -- ---- Volume
    v_lots := p_lots;
    IF v_lots IS NULL OR v_lots <= 0 THEN
        RAISE EXCEPTION 'BAD_LOTS: volume must be greater than zero' USING ERRCODE = '22023';
    END IF;
    IF v_lots < v_inst.min_lots OR v_lots > v_inst.max_lots THEN
        RAISE EXCEPTION 'BAD_LOTS: volume for % must be between % and % lots (got %)',
            p_symbol, v_inst.min_lots, v_inst.max_lots, v_lots USING ERRCODE = '22023';
    END IF;
    IF v_inst.lot_step > 0 AND ROUND(MOD(v_lots, v_inst.lot_step), 8) <> 0 THEN
        RAISE EXCEPTION 'BAD_LOTS: volume for % must be a multiple of % lots (got %)',
            p_symbol, v_inst.lot_step, v_lots USING ERRCODE = '22023';
    END IF;

    -- ---- Leverage
    v_lev := COALESCE(p_leverage, 100);
    IF v_lev <= 0 THEN
        RAISE EXCEPTION 'BAD_LEVERAGE: leverage must be positive' USING ERRCODE = '22023';
    END IF;
    IF v_lev > v_inst.max_leverage THEN
        RAISE EXCEPTION 'BAD_LEVERAGE: maximum leverage for % is 1:%', p_symbol, v_inst.max_leverage
            USING ERRCODE = '22023';
    END IF;

    -- ---- Authoritative price
    v_q := public.fx_resolve_quote(p_symbol, p_quotes, TRUE, TRUE);

    IF v_type = 'market' THEN
        v_entry := CASE WHEN v_side = 'buy' THEN v_q.ask ELSE v_q.bid END;

        -- Protect the user from being filled far from the price they saw.
        IF p_requested_price IS NOT NULL AND p_requested_price > 0
           AND ABS(v_entry - p_requested_price) / p_requested_price > v_cfg.max_slippage_fraction
        THEN
            RAISE EXCEPTION
                'SLIPPAGE_EXCEEDED: % moved from % to % (max % pct slippage)',
                p_symbol, p_requested_price, v_entry, (v_cfg.max_slippage_fraction * 100)
                USING ERRCODE = '22023';
        END IF;
    ELSE
        IF p_target_price IS NULL OR p_target_price <= 0 THEN
            RAISE EXCEPTION 'BAD_TARGET_PRICE: % orders require a positive trigger price', v_type
                USING ERRCODE = '22023';
        END IF;
        v_entry := p_target_price;

        -- A limit buys below the market and a stop buys above it. Getting this
        -- backwards used to create an order that fired on the very next tick.
        IF v_type = 'limit' AND v_side = 'buy'  AND p_target_price >= v_q.ask THEN
            RAISE EXCEPTION 'BAD_TARGET_PRICE: a BUY LIMIT must sit below the current ask (%)', v_q.ask
                USING ERRCODE = '22023';
        ELSIF v_type = 'limit' AND v_side = 'sell' AND p_target_price <= v_q.bid THEN
            RAISE EXCEPTION 'BAD_TARGET_PRICE: a SELL LIMIT must sit above the current bid (%)', v_q.bid
                USING ERRCODE = '22023';
        ELSIF v_type = 'stop'  AND v_side = 'buy'  AND p_target_price <= v_q.ask THEN
            RAISE EXCEPTION 'BAD_TARGET_PRICE: a BUY STOP must sit above the current ask (%)', v_q.ask
                USING ERRCODE = '22023';
        ELSIF v_type = 'stop'  AND v_side = 'sell' AND p_target_price >= v_q.bid THEN
            RAISE EXCEPTION 'BAD_TARGET_PRICE: a SELL STOP must sit below the current bid (%)', v_q.bid
                USING ERRCODE = '22023';
        END IF;
    END IF;

    -- ---- Stop loss / take profit must be on the correct side of the entry.
    IF p_stop_loss IS NOT NULL THEN
        IF p_stop_loss <= 0 THEN
            RAISE EXCEPTION 'BAD_STOP_LOSS: stop loss must be positive' USING ERRCODE = '22023';
        END IF;
        IF v_side = 'buy' AND p_stop_loss >= v_entry THEN
            RAISE EXCEPTION 'BAD_STOP_LOSS: for a BUY the stop loss (%) must be below the entry (%)',
                p_stop_loss, v_entry USING ERRCODE = '22023';
        END IF;
        IF v_side = 'sell' AND p_stop_loss <= v_entry THEN
            RAISE EXCEPTION 'BAD_STOP_LOSS: for a SELL the stop loss (%) must be above the entry (%)',
                p_stop_loss, v_entry USING ERRCODE = '22023';
        END IF;
    END IF;

    IF p_take_profit IS NOT NULL THEN
        IF p_take_profit <= 0 THEN
            RAISE EXCEPTION 'BAD_TAKE_PROFIT: take profit must be positive' USING ERRCODE = '22023';
        END IF;
        IF v_side = 'buy' AND p_take_profit <= v_entry THEN
            RAISE EXCEPTION 'BAD_TAKE_PROFIT: for a BUY the take profit (%) must be above the entry (%)',
                p_take_profit, v_entry USING ERRCODE = '22023';
        END IF;
        IF v_side = 'sell' AND p_take_profit >= v_entry THEN
            RAISE EXCEPTION 'BAD_TAKE_PROFIT: for a SELL the take profit (%) must be below the entry (%)',
                p_take_profit, v_entry USING ERRCODE = '22023';
        END IF;
    END IF;

    -- ---- Money: lock the wallet FIRST (fixed lock order), then reserve margin.
    v_wallet := public.fx_lock_wallet(v_uid);

    v_margin := public.fx_calc_margin(v_lots, v_inst.contract_size, v_entry, v_lev, v_q.quote_to_usd);
    v_comm   := ROUND(v_inst.commission_per_lot * v_lots, 4);

    v_trade_id := 'POS-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', '') FROM 1 FOR 10));
    v_order_id := 'ORD-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', '') FROM 1 FOR 10));

    IF v_type = 'market' THEN
        v_unreal := public.fx_unrealized_total(v_uid, NULL);
        v_free   := (v_wallet.balance + v_unreal) - v_wallet.held_margin;

        IF v_free < (v_margin + v_comm) THEN
            RAISE EXCEPTION
                'INSUFFICIENT_MARGIN: % requires % but only % of free margin is available',
                p_symbol, ROUND(v_margin + v_comm, 2), ROUND(v_free, 2)
                USING ERRCODE = '22023';
        END IF;

        v_status  := 'open';
        v_new_bal := v_wallet.balance - v_comm;
    ELSE
        -- Pending orders reserve no margin; it is validated again at trigger time
        -- (see fx_activate_trade), because the account can change while resting.
        v_status  := 'pending';
        v_new_bal := v_wallet.balance;
    END IF;

    INSERT INTO public.trades (
        id, user_id, order_id, symbol, side, type, status,
        lots, contract_size, open_price, current_price, target_price,
        stop_loss, take_profit, required_margin, leverage,
        commission, swap, quote_to_usd_rate, requested_price,
        open_bid, open_ask, spread_at_open, price_source,
        client_request_id, expires_at, open_time, filled_at, created_at, updated_at
    ) VALUES (
        v_trade_id, v_uid, v_order_id, p_symbol, v_side, v_type, v_status,
        v_lots, v_inst.contract_size, v_entry, v_entry,
        CASE WHEN v_type = 'market' THEN NULL ELSE p_target_price END,
        p_stop_loss, p_take_profit,
        CASE WHEN v_type = 'market' THEN v_margin ELSE 0 END,
        v_lev,
        CASE WHEN v_type = 'market' THEN v_comm ELSE 0 END,
        0, COALESCE(v_q.quote_to_usd, 1), p_requested_price,
        v_q.bid, v_q.ask, (v_q.ask - v_q.bid), v_q.source,
        p_client_request_id, p_expires_at, NOW(),
        CASE WHEN v_type = 'market' THEN NOW() ELSE NULL END,
        NOW(), NOW()
    );

    IF v_type = 'market' THEN
        UPDATE public.wallets
           SET held_margin = held_margin + v_margin,
               balance     = v_new_bal,
               updated_at  = NOW()
         WHERE user_id = v_uid AND currency = 'USD';

        PERFORM public.fx_post_ledger(
            v_uid, 'margin_lock', v_margin, v_new_bal, v_trade_id,
            format('Margin locked for %s %s %s lots @ %s', v_side, p_symbol, v_lots, v_entry),
            'margin_lock:' || v_trade_id);

        IF v_comm > 0 THEN
            PERFORM public.fx_post_ledger(
                v_uid, 'commission', -v_comm, v_new_bal, v_trade_id,
                format('Commission on %s (%s lots)', p_symbol, v_lots),
                'commission:' || v_trade_id);
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'trade_id', v_trade_id,
        'order_id', v_order_id,
        'trade_status', v_status,
        'symbol', p_symbol,
        'side', v_side,
        'type', v_type,
        'lots', v_lots,
        'open_price', v_entry,
        'target_price', CASE WHEN v_type = 'market' THEN NULL ELSE p_target_price END,
        'stop_loss', p_stop_loss,
        'take_profit', p_take_profit,
        'leverage', v_lev,
        'required_margin', CASE WHEN v_type = 'market' THEN v_margin ELSE 0 END,
        'commission', CASE WHEN v_type = 'market' THEN v_comm ELSE 0 END,
        'quote_to_usd_rate', COALESCE(v_q.quote_to_usd, 1),
        'bid', v_q.bid,
        'ask', v_q.ask,
        'price_source', v_q.source,
        'account', public.fx_account_snapshot(v_uid, NULL));
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. CLOSE A POSITION
--
-- The close price is NEVER taken from the client. The old signature accepted
-- `p_close_price NUMERIC` and settled it straight into the wallet, which let any
-- caller mint an arbitrary profit — and it never checked trade ownership, so it
-- could be aimed at another user's position.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_close_trade(
    p_trade_id TEXT,
    p_quotes   JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid   TEXT;
    v_t     public.trades;
    v_q     public.fx_quote_t;
    v_fill  NUMERIC;
    v_res   JSONB;
BEGIN
    v_uid := public.fx_require_user_id();

    SELECT * INTO v_t FROM public.trades WHERE id = p_trade_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRADE_NOT_FOUND: no trade %', p_trade_id USING ERRCODE = '22023';
    END IF;

    -- Ownership check.
    IF v_t.user_id <> v_uid AND NOT public.fx_is_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN: trade % does not belong to this account', p_trade_id
            USING ERRCODE = '42501';
    END IF;

    IF v_t.status <> 'open' THEN
        RETURN jsonb_build_object(
            'status', 'already_closed',
            'trade_id', p_trade_id,
            'trade_status', v_t.status,
            'close_reason', v_t.close_reason,
            'realized_pnl', v_t.realized_pnl,
            'account', public.fx_account_snapshot(v_t.user_id, NULL));
    END IF;

    v_q    := public.fx_resolve_quote(v_t.symbol, p_quotes, TRUE, TRUE);
    v_fill := CASE WHEN v_t.side = 'buy' THEN v_q.bid ELSE v_q.ask END;

    -- Fixed lock order: wallet, then the trade row inside fx_close_trade_row.
    PERFORM public.fx_lock_wallet(v_t.user_id);

    v_res := public.fx_close_trade_row(
        p_trade_id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, 'MANUAL', v_q.source);

    RETURN v_res || jsonb_build_object('account', public.fx_account_snapshot(v_t.user_id, NULL));
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. CANCEL A PENDING ORDER
--    A filled order can no longer be cancelled: the conditional UPDATE only
--    matches status='pending', so a cancel racing a trigger loses safely.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_cancel_pending_order(p_order_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid   TEXT;
    v_t     public.trades;
    v_fresh public.trades;
BEGIN
    v_uid := public.fx_require_user_id();

    SELECT * INTO v_t FROM public.trades
    WHERE (id = p_order_id OR order_id = p_order_id)
    ORDER BY CASE WHEN id = p_order_id THEN 0 ELSE 1 END
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: no order %', p_order_id USING ERRCODE = '22023';
    END IF;

    IF v_t.user_id <> v_uid AND NOT public.fx_is_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN: order % does not belong to this account', p_order_id
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.trades
       SET status = 'cancelled', cancelled_at = NOW(), updated_at = NOW(),
           close_reason = 'CANCELLED'
     WHERE id = v_t.id AND status = 'pending';

    IF NOT FOUND THEN
        SELECT * INTO v_fresh FROM public.trades WHERE id = v_t.id;
        RETURN jsonb_build_object(
            'status', CASE WHEN v_fresh.status = 'cancelled' THEN 'already_cancelled'
                           ELSE 'already_filled' END,
            'order_id', v_fresh.id,
            'trade_status', v_fresh.status,
            'message', format('Order is %s and can no longer be cancelled.', v_fresh.status));
    END IF;

    RETURN jsonb_build_object(
        'status', 'cancelled',
        'order_id', v_t.id,
        'trade_status', 'cancelled',
        'account', public.fx_account_snapshot(v_t.user_id, NULL));
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. RISK EVALUATION ENGINE
--
-- One atomic pass over an account: expire, trigger pending orders, execute
-- SL/TP, then liquidate until the margin level recovers. Shared by the app
-- (rpc_sync_account) and by the offline cron (rpc_sweep_accounts), so SL/TP and
-- stop-out behave identically whether or not Flutter is running.
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

    -- ---- 4a. Expire resting orders that outlived their validity.
    UPDATE public.trades
       SET status = 'expired', close_reason = 'EXPIRED', updated_at = NOW()
     WHERE user_id = p_user_id AND status = 'pending'
       AND expires_at IS NOT NULL AND expires_at <= NOW();
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    -- ---- 4b. Trigger pending limit / stop orders on the correct book side.
    FOR v_row IN
        SELECT id, side, type, target_price, symbol
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'pending'
        ORDER BY created_at
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, p_quotes, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL OR v_row.target_price IS NULL;

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

    -- ---- 4c. Stop loss / take profit. Risk is checked before reward.
    FOR v_row IN
        SELECT id, side, symbol, stop_loss, take_profit
        FROM public.trades
        WHERE user_id = p_user_id AND status = 'open'
          AND (stop_loss IS NOT NULL OR take_profit IS NOT NULL)
        ORDER BY open_time
    LOOP
        v_q := public.fx_resolve_quote(v_row.symbol, p_quotes, FALSE, FALSE);
        CONTINUE WHEN v_q.bid IS NULL;

        v_reason := NULL;
        IF v_row.side = 'buy' THEN
            IF v_row.stop_loss IS NOT NULL AND v_q.bid <= v_row.stop_loss THEN
                v_reason := 'STOP_LOSS'; v_fill := v_row.stop_loss;
            ELSIF v_row.take_profit IS NOT NULL AND v_q.bid >= v_row.take_profit THEN
                v_reason := 'TAKE_PROFIT'; v_fill := v_row.take_profit;
            END IF;
        ELSE
            IF v_row.stop_loss IS NOT NULL AND v_q.ask >= v_row.stop_loss THEN
                v_reason := 'STOP_LOSS'; v_fill := v_row.stop_loss;
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

    -- ---- 4d. Stop-out: liquidate worst loser, recompute, repeat until recovered.
    LOOP
        v_snap  := public.fx_account_snapshot(p_user_id, p_quotes);
        v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

        EXIT WHEN v_level IS NULL;                                   -- nothing at risk
        EXIT WHEN v_level > v_cfg.stop_out_level_pct;                 -- recovered
        EXIT WHEN (v_snap ->> 'open_positions')::INTEGER = 0;         -- nothing left
        EXIT WHEN v_passes >= v_cfg.max_liquidation_passes;           -- cascade guard

        SELECT t.id, t.side, t.symbol INTO v_row
        FROM public.trades t
        CROSS JOIN LATERAL public.fx_resolve_quote(t.symbol, p_quotes, FALSE, FALSE) q
        WHERE t.user_id = p_user_id AND t.status = 'open'
        ORDER BY public.fx_calc_pnl(
                    t.side, t.open_price,
                    COALESCE(CASE WHEN t.side = 'buy' THEN q.bid ELSE q.ask END,
                             t.current_price, t.open_price),
                    t.lots, t.contract_size,
                    COALESCE(q.quote_to_usd, t.quote_to_usd_rate)) ASC
        LIMIT 1;
        EXIT WHEN NOT FOUND;

        v_q := public.fx_resolve_quote(v_row.symbol, p_quotes, FALSE, FALSE);
        v_fill := CASE WHEN v_row.side = 'buy' THEN v_q.bid ELSE v_q.ask END;
        EXIT WHEN v_fill IS NULL;

        v_res := public.fx_close_trade_row(
            v_row.id, v_fill, v_q.bid, v_q.ask, v_q.quote_to_usd, 'STOP_OUT', v_q.source);

        -- Never loop on a close that did not actually happen.
        EXIT WHEN (v_res ->> 'status') <> 'success';

        v_closed := v_closed || v_res;
        v_passes := v_passes + 1;
    END LOOP;

    v_snap := public.fx_account_snapshot(p_user_id, p_quotes);
    v_level := (v_snap ->> 'margin_level_pct')::NUMERIC;

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
-- 5. CLIENT ENTRY POINTS FOR RISK / STATE
-- ------------------------------------------------------------------------------

-- Called by the app on a throttled tick. Client quotes are band-validated and
-- persisted first; the evaluation itself then reads only the stored book, so a
-- client can never hand different prices to the pricing and the settlement step.
CREATE OR REPLACE FUNCTION public.rpc_sync_account(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid TEXT;
    v_sym TEXT;
BEGIN
    v_uid := public.fx_require_user_id();

    FOR v_sym IN
        SELECT DISTINCT symbol FROM public.trades
        WHERE user_id = v_uid AND status IN ('open', 'pending')
    LOOP
        BEGIN
            PERFORM public.fx_resolve_quote(v_sym, p_quotes, TRUE, FALSE);
        EXCEPTION WHEN OTHERS THEN
            -- Out-of-band or malformed quote: keep the stored price, keep going.
            NULL;
        END;
    END LOOP;

    RETURN public.fx_evaluate_account(v_uid, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_account_state(p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid TEXT;
BEGIN
    v_uid := public.fx_require_user_id();
    RETURN public.fx_account_snapshot(v_uid, p_quotes);
END;
$$;

-- Offline engine. Point pg_cron (or a scheduled Edge Function) at this so SL/TP,
-- pending triggers and stop-out keep running with the app closed:
--   SELECT cron.schedule('fx-sweep', '*/1 * * * *', $$SELECT public.rpc_sweep_accounts()$$);
CREATE OR REPLACE FUNCTION public.rpc_sweep_accounts(p_max_accounts INTEGER DEFAULT 500)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid       TEXT;
    v_res       JSONB;
    v_accounts  INTEGER := 0;
    v_closed    INTEGER := 0;
    v_triggered INTEGER := 0;
    v_errors    INTEGER := 0;
BEGIN
    PERFORM public.fx_require_admin();

    FOR v_uid IN
        SELECT DISTINCT user_id FROM public.trades
        WHERE status IN ('open', 'pending')
        LIMIT p_max_accounts
    LOOP
        BEGIN
            v_res := public.fx_evaluate_account(v_uid, NULL);
            v_accounts  := v_accounts + 1;
            v_closed    := v_closed + jsonb_array_length(v_res -> 'closed');
            v_triggered := v_triggered + jsonb_array_length(v_res -> 'triggered');
        EXCEPTION WHEN OTHERS THEN
            -- One bad account must not abort the whole sweep.
            v_errors := v_errors + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'accounts_evaluated', v_accounts,
        'positions_closed', v_closed,
        'orders_triggered', v_triggered,
        'errors', v_errors,
        'swept_at', NOW());
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. ADMIN BALANCE ADJUSTMENT (authorized + audited + idempotent)
--    Replaces the client-side wallet upsert in admin_portal_screen.dart.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_adjust_balance(
    p_user_id    TEXT,
    p_amount     NUMERIC,
    p_reason     TEXT,
    p_request_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin  TEXT;
    v_wallet public.wallets;
    v_new    NUMERIC;
    v_adj_id UUID;
    v_prev   public.admin_balance_adjustments;
BEGIN
    v_admin := public.fx_require_admin();

    IF p_amount IS NULL OR p_amount = 0 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: adjustment amount must be non-zero' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(TRIM(p_reason), '') = '' THEN
        RAISE EXCEPTION 'REASON_REQUIRED: every balance adjustment needs an audit reason'
            USING ERRCODE = '22023';
    END IF;

    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.admin_balance_adjustments WHERE request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object(
                'status', 'already_applied',
                'adjustment_id', v_prev.id,
                'balance_after', v_prev.balance_after);
        END IF;
    END IF;

    v_wallet := public.fx_lock_wallet(p_user_id);
    v_new := v_wallet.balance + p_amount;

    IF v_new < 0 THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: adjustment would drive the balance to %', ROUND(v_new, 2)
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.wallets SET balance = v_new, updated_at = NOW()
     WHERE user_id = p_user_id AND currency = 'USD';

    INSERT INTO public.admin_balance_adjustments
        (user_id, admin_id, amount, reason, balance_before, balance_after, request_id)
    VALUES (p_user_id, v_admin, p_amount, TRIM(p_reason), v_wallet.balance, v_new, p_request_id)
    RETURNING id INTO v_adj_id;

    PERFORM public.fx_post_ledger(
        p_user_id, 'admin_adjustment', p_amount, v_new, v_adj_id::TEXT,
        format('Admin adjustment by %s: %s', v_admin, TRIM(p_reason)),
        'admin_adj:' || v_adj_id::TEXT);

    RETURN jsonb_build_object(
        'status', 'success',
        'adjustment_id', v_adj_id,
        'user_id', p_user_id,
        'amount', p_amount,
        'balance_before', v_wallet.balance,
        'balance_after', v_new);
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. WITHDRAWALS — request holds the funds, admin settles them.
--    Replaces TradingEngineCubit.withdrawFunds(), which debited a client-side
--    number and never touched the authoritative wallet.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_request_withdrawal(
    p_amount      NUMERIC,
    p_method      TEXT DEFAULT NULL,
    p_destination TEXT DEFAULT NULL,
    p_request_id  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid    TEXT;
    v_cfg    public.broker_config;
    v_wallet public.wallets;
    v_unreal NUMERIC;
    v_free   NUMERIC;
    v_new    NUMERIC;
    v_id     UUID;
    v_kyc    TEXT;
    v_prev   public.withdrawals;
BEGIN
    v_uid := public.fx_require_user_id();
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: withdrawal amount must be positive' USING ERRCODE = '22023';
    END IF;

    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_prev FROM public.withdrawals WHERE request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate', 'withdrawal_id', v_prev.id,
                                      'withdrawal_status', v_prev.status);
        END IF;
    END IF;

    -- Same rule as rpc_open_trade: the database can only enforce KYC when the
    -- compliance module is actually deployed. Without it, withdrawals fall back
    -- to KycPolicy.canWithdraw on the client rather than being blocked outright.
    IF v_cfg.require_kyc_for_withdraw AND public.fx_kyc_module_installed() THEN
        v_kyc := public.fx_kyc_status(v_uid);
        IF COALESCE(v_kyc, 'NOT_STARTED') <> 'APPROVED' THEN
            RAISE EXCEPTION 'KYC_REQUIRED: withdrawals require approved identity verification'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    v_wallet := public.fx_lock_wallet(v_uid);
    v_unreal := public.fx_unrealized_total(v_uid, NULL);
    v_free   := (v_wallet.balance + v_unreal) - v_wallet.held_margin;

    IF v_wallet.balance < p_amount OR v_free < p_amount THEN
        RAISE EXCEPTION
            'INSUFFICIENT_FUNDS: withdrawable amount is % (balance %, free margin %)',
            ROUND(LEAST(v_wallet.balance, v_free), 2), ROUND(v_wallet.balance, 2), ROUND(v_free, 2)
            USING ERRCODE = '22023';
    END IF;

    v_new := v_wallet.balance - p_amount;

    UPDATE public.wallets SET balance = v_new, updated_at = NOW()
     WHERE user_id = v_uid AND currency = 'USD';

    INSERT INTO public.withdrawals (user_id, amount, method, destination, request_id)
    VALUES (v_uid, p_amount, p_method, p_destination, p_request_id)
    RETURNING id INTO v_id;

    PERFORM public.fx_post_ledger(
        v_uid, 'withdrawal_hold', -p_amount, v_new, v_id::TEXT,
        format('Withdrawal request held (%s)', COALESCE(p_method, 'n/a')),
        'withdrawal_hold:' || v_id::TEXT);

    RETURN jsonb_build_object(
        'status', 'success',
        'withdrawal_id', v_id,
        'withdrawal_status', 'PENDING',
        'amount', p_amount,
        'balance_after', v_new);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_review_withdrawal(
    p_withdrawal_id UUID,
    p_approve       BOOLEAN,
    p_reason        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_w     public.withdrawals;
    v_new   NUMERIC;
BEGIN
    v_admin := public.fx_require_admin();

    SELECT * INTO v_w FROM public.withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'WITHDRAWAL_NOT_FOUND: %', p_withdrawal_id USING ERRCODE = '22023';
    END IF;
    IF v_w.status <> 'PENDING' THEN
        RETURN jsonb_build_object('status', 'already_reviewed', 'withdrawal_status', v_w.status);
    END IF;

    PERFORM public.fx_lock_wallet(v_w.user_id);

    IF p_approve THEN
        UPDATE public.withdrawals
           SET status = 'APPROVED', reviewed_by = v_admin, reviewed_at = NOW(), updated_at = NOW()
         WHERE id = p_withdrawal_id;

        SELECT balance INTO v_new FROM public.wallets
        WHERE user_id = v_w.user_id AND currency = 'USD';

        PERFORM public.fx_post_ledger(
            v_w.user_id, 'withdrawal', -v_w.amount, v_new, p_withdrawal_id::TEXT,
            format('Withdrawal settled by %s', v_admin),
            'withdrawal:' || p_withdrawal_id::TEXT);

        RETURN jsonb_build_object('status', 'success', 'withdrawal_status', 'APPROVED',
                                  'balance_after', v_new);
    END IF;

    -- Rejected: return the held funds.
    SELECT balance + v_w.amount INTO v_new FROM public.wallets
    WHERE user_id = v_w.user_id AND currency = 'USD';

    UPDATE public.wallets SET balance = v_new, updated_at = NOW()
     WHERE user_id = v_w.user_id AND currency = 'USD';

    UPDATE public.withdrawals
       SET status = 'REJECTED', reviewed_by = v_admin, reviewed_at = NOW(),
           reject_reason = p_reason, updated_at = NOW()
     WHERE id = p_withdrawal_id;

    PERFORM public.fx_post_ledger(
        v_w.user_id, 'withdrawal_refund', v_w.amount, v_new, p_withdrawal_id::TEXT,
        format('Withdrawal rejected by %s: %s', v_admin, COALESCE(p_reason, 'no reason given')),
        'withdrawal_refund:' || p_withdrawal_id::TEXT);

    RETURN jsonb_build_object('status', 'success', 'withdrawal_status', 'REJECTED',
                              'balance_after', v_new);
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. EXECUTION GRANTS
--    Internal primitives stay unreachable from the client; only the vetted
--    entry points are callable, and each re-derives the caller from the JWT.
-- ------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fx_close_trade_row(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_activate_trade(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_evaluate_account(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_lock_wallet(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_post_ledger(TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_resolve_quote(TEXT, JSONB, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_unrealized_total(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_account_snapshot(TEXT, JSONB) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_open_trade(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB, NUMERIC, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_close_trade(TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_pending_order(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_sync_account(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_account_state(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) TO authenticated;

-- Admin-gated (the function itself calls fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_adjust_balance(TEXT, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_review_withdrawal(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_publish_quotes(JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_sweep_accounts(INTEGER) TO service_role;
