-- ==============================================================================
-- MIGRATION: 20261001000100_trading_rpcs.sql
--
-- The authoritative trading engine. Every function that moves money is
-- SECURITY DEFINER, locks rows in a fixed order (wallet -> trades), and is
-- idempotent so a retry / double-tap / duplicated realtime event can never
-- produce two financial transactions.
--
-- Replaces the previous rpc_open_trade / rpc_close_trade which:
--   * fell back to a hard-coded user id when auth.uid() was NULL
--   * created wallets pre-funded with $10,000
--   * did not verify trade OWNERSHIP on close (any user could close any trade)
--   * accepted the CLOSE PRICE from the client (mint-money hole)
--   * had no ON CONFLICT idempotency (a retry re-locked margin)
--   * hard-coded type='market' so pending orders could not be stored
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 0. RESULT TYPE FOR RESOLVED QUOTES
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    CREATE TYPE public.fx_quote_t AS (
        symbol       TEXT,
        bid          NUMERIC,
        ask          NUMERIC,
        quote_to_usd NUMERIC,
        source       TEXT,
        as_of        TIMESTAMPTZ
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ------------------------------------------------------------------------------
-- 1. PRICE RESOLUTION
-- ------------------------------------------------------------------------------

-- USD value of one unit of p_code, derived from the stored quote book.
CREATE OR REPLACE FUNCTION public.fx_usd_per_currency(p_code TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE v_mid NUMERIC;
BEGIN
    IF p_code IS NULL OR UPPER(p_code) IN ('', 'USD') THEN
        RETURN 1;
    END IF;

    SELECT (bid + ask) / 2 INTO v_mid FROM public.market_quotes
    WHERE symbol = UPPER(p_code) || '/USD';
    IF v_mid IS NOT NULL AND v_mid > 0 THEN RETURN v_mid; END IF;

    SELECT (bid + ask) / 2 INTO v_mid FROM public.market_quotes
    WHERE symbol = 'USD/' || UPPER(p_code);
    IF v_mid IS NOT NULL AND v_mid > 0 THEN RETURN ROUND(1 / v_mid, 10); END IF;

    RETURN 1; -- unknown currency: behave as USD-quoted rather than zeroing PnL
END;
$$;

-- Resolve the authoritative bid/ask for p_symbol.
--
-- Priority:
--   1. A fresh quote published by the price publisher (service_role).
--   2. A client-submitted quote, only when it sits inside
--      broker_config.quote_band_fraction of the last known price. Stored with
--      source='client' so every client-priced fill stays auditable.
--   3. The last stored quote, however stale (used by the offline cron sweep).
--
-- p_persist=false makes the call side-effect free (used for read-only snapshots).
-- p_strict=false returns NULL prices instead of raising when nothing is known.
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
    v_cfg    public.broker_config;
    v_mq     public.market_quotes;
    v_in     JSONB;
    v_bid    NUMERIC;
    v_ask    NUMERIC;
    v_rate   NUMERIC;
    v_quote  TEXT;
    v_ref    NUMERIC;
    v_out    public.fx_quote_t;
BEGIN
    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    SELECT * INTO v_mq  FROM public.market_quotes WHERE symbol = p_symbol;

    -- 1. Fresh publisher quote wins unconditionally.
    IF v_mq.symbol IS NOT NULL
       AND v_mq.source = 'publisher'
       AND v_mq.updated_at > NOW() - make_interval(secs => v_cfg.quote_max_age_seconds)
    THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'publisher', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    -- 2. Client-submitted quote, band-validated.
    v_in := p_quotes -> p_symbol;
    IF v_in IS NOT NULL AND v_cfg.allow_client_quotes THEN
        v_bid := (v_in ->> 'bid')::NUMERIC;
        v_ask := (v_in ->> 'ask')::NUMERIC;

        IF v_bid IS NULL OR v_ask IS NULL OR v_bid <= 0 OR v_ask < v_bid THEN
            RAISE EXCEPTION 'BAD_QUOTE: % submitted an invalid bid/ask (%/%)', p_symbol, v_bid, v_ask
                USING ERRCODE = '22023';
        END IF;

        SELECT quote_currency INTO v_quote FROM public.instruments WHERE symbol = p_symbol;
        v_rate := COALESCE((v_in ->> 'rate')::NUMERIC, public.fx_usd_per_currency(v_quote));
        IF v_rate IS NULL OR v_rate <= 0 THEN v_rate := 1; END IF;

        IF v_mq.symbol IS NOT NULL THEN
            v_ref := (v_mq.bid + v_mq.ask) / 2;
            IF v_ref > 0
               AND ABS(((v_bid + v_ask) / 2) - v_ref) / v_ref > v_cfg.quote_band_fraction
            THEN
                RAISE EXCEPTION
                    'QUOTE_OUT_OF_BAND: % submitted a mid of % but the last known mid is % (max % pct deviation)',
                    p_symbol, ((v_bid + v_ask) / 2), v_ref, (v_cfg.quote_band_fraction * 100)
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        IF p_persist THEN
            INSERT INTO public.market_quotes (symbol, bid, ask, quote_to_usd, source, updated_at)
            VALUES (p_symbol, v_bid, v_ask, v_rate, 'client', NOW())
            ON CONFLICT (symbol) DO UPDATE
                SET bid = EXCLUDED.bid,
                    ask = EXCLUDED.ask,
                    quote_to_usd = EXCLUDED.quote_to_usd,
                    source = 'client',
                    updated_at = NOW();
        END IF;

        v_out := ROW(p_symbol, v_bid, v_ask, v_rate, 'client', NOW())::public.fx_quote_t;
        RETURN v_out;
    END IF;

    -- 3. Stale stored quote (offline sweep path).
    IF v_mq.symbol IS NOT NULL THEN
        v_out := ROW(p_symbol, v_mq.bid, v_mq.ask, v_mq.quote_to_usd, 'stale', v_mq.updated_at)::public.fx_quote_t;
        RETURN v_out;
    END IF;

    IF p_strict THEN
        RAISE EXCEPTION 'NO_QUOTE: no authoritative price is available for %', p_symbol
            USING ERRCODE = '22023';
    END IF;

    v_out := ROW(p_symbol, NULL::NUMERIC, NULL::NUMERIC, NULL::NUMERIC, 'none', NULL::TIMESTAMPTZ)::public.fx_quote_t;
    RETURN v_out;
END;
$$;

-- Price publisher entry point. service_role / admin only.
CREATE OR REPLACE FUNCTION public.rpc_publish_quotes(p_quotes JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sym   TEXT;
    v_row   JSONB;
    v_count INTEGER := 0;
BEGIN
    PERFORM public.fx_require_admin();

    FOR v_sym, v_row IN SELECT key, value FROM jsonb_each(COALESCE(p_quotes, '{}'::JSONB)) LOOP
        IF NOT EXISTS (SELECT 1 FROM public.instruments WHERE symbol = v_sym) THEN
            CONTINUE; -- ignore symbols the broker does not offer
        END IF;
        IF (v_row ->> 'bid') IS NULL OR (v_row ->> 'ask') IS NULL THEN CONTINUE; END IF;
        IF (v_row ->> 'bid')::NUMERIC <= 0 OR (v_row ->> 'ask')::NUMERIC < (v_row ->> 'bid')::NUMERIC THEN
            CONTINUE;
        END IF;

        INSERT INTO public.market_quotes (symbol, bid, ask, quote_to_usd, source, updated_at)
        VALUES (
            v_sym,
            (v_row ->> 'bid')::NUMERIC,
            (v_row ->> 'ask')::NUMERIC,
            GREATEST(COALESCE((v_row ->> 'rate')::NUMERIC, 1), 0.0000000001),
            'publisher',
            NOW()
        )
        ON CONFLICT (symbol) DO UPDATE
            SET bid = EXCLUDED.bid, ask = EXCLUDED.ask,
                quote_to_usd = EXCLUDED.quote_to_usd,
                source = 'publisher', updated_at = NOW();
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('status', 'success', 'published', v_count);
END;
$$;

-- ------------------------------------------------------------------------------
-- 2. MONEY MATH (identical formulas to lib/core/math/money_math.dart)
-- ------------------------------------------------------------------------------

-- margin = (lots * contract_size * price * quote_to_usd) / leverage
CREATE OR REPLACE FUNCTION public.fx_calc_margin(
    p_lots NUMERIC, p_contract_size NUMERIC, p_price NUMERIC,
    p_leverage NUMERIC, p_rate NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_leverage IS NULL OR p_leverage <= 0 THEN 0
        ELSE ROUND((p_lots * p_contract_size * p_price * COALESCE(p_rate, 1)) / p_leverage, 4)
    END;
$$;

-- pnl_usd = (+/-(close - open)) * lots * contract_size * quote_to_usd
CREATE OR REPLACE FUNCTION public.fx_calc_pnl(
    p_side TEXT, p_open NUMERIC, p_close NUMERIC,
    p_lots NUMERIC, p_contract_size NUMERIC, p_rate NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
    SELECT ROUND(
        (CASE WHEN p_side = 'buy' THEN (p_close - p_open) ELSE (p_open - p_close) END)
        * p_lots * p_contract_size * COALESCE(p_rate, 1), 4);
$$;

-- Total floating PnL of a user's open book at the supplied / stored quotes.
CREATE OR REPLACE FUNCTION public.fx_unrealized_total(p_user_id TEXT, p_quotes JSONB DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE sql
SET search_path = public
AS $$
    SELECT COALESCE(SUM(
        public.fx_calc_pnl(
            t.side,
            t.open_price,
            COALESCE(
                CASE WHEN t.side = 'buy' THEN q.bid ELSE q.ask END,
                t.current_price,
                t.open_price
            ),
            t.lots,
            t.contract_size,
            COALESCE(q.quote_to_usd, t.quote_to_usd_rate)
        )
    ), 0)
    FROM public.trades t
    CROSS JOIN LATERAL public.fx_resolve_quote(t.symbol, p_quotes, FALSE, FALSE) q
    WHERE t.user_id = p_user_id AND t.status = 'open';
$$;

-- Equity / used margin / free margin / margin level for one account.
CREATE OR REPLACE FUNCTION public.fx_account_snapshot(p_user_id TEXT, p_quotes JSONB DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_bal    NUMERIC := 0;
    v_held   NUMERIC := 0;
    v_unreal NUMERIC := 0;
    v_equity NUMERIC;
    v_free   NUMERIC;
    v_level  NUMERIC;
    v_open   INTEGER := 0;
    v_pend   INTEGER := 0;
BEGIN
    SELECT balance, held_margin INTO v_bal, v_held
    FROM public.wallets WHERE user_id = p_user_id AND currency = 'USD';

    v_bal    := COALESCE(v_bal, 0);
    v_held   := COALESCE(v_held, 0);
    v_unreal := public.fx_unrealized_total(p_user_id, p_quotes);
    v_equity := v_bal + v_unreal;
    v_free   := v_equity - v_held;
    v_level  := CASE WHEN v_held > 0 THEN ROUND((v_equity / v_held) * 100, 4) ELSE NULL END;

    SELECT COUNT(*) FILTER (WHERE status = 'open'),
           COUNT(*) FILTER (WHERE status = 'pending')
      INTO v_open, v_pend
    FROM public.trades WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'balance', v_bal,
        'used_margin', v_held,
        'unrealized_pnl', v_unreal,
        'equity', v_equity,
        'free_margin', v_free,
        'margin_level_pct', v_level,
        'open_positions', v_open,
        'pending_orders', v_pend
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 2b. OPTIONAL KYC MODULE LOOKUP
--
-- public.kyc_profiles ships with the compliance module, which is not installed
-- on every project. A plain `SELECT ... FROM public.kyc_profiles` inside a
-- function fails at RUN TIME with `relation "public.kyc_profiles" does not
-- exist` — which took down order placement entirely on a database without it.
--
-- to_regclass() + EXECUTE keeps the reference dynamic, so the trading engine
-- works with or without the compliance module. A missing table returns NULL,
-- which the callers treat as "not verified" — the safe direction.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_kyc_module_installed()
RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = public
AS $$ SELECT to_regclass('public.kyc_profiles') IS NOT NULL $$;

CREATE OR REPLACE FUNCTION public.fx_kyc_status(p_user_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE v_status TEXT;
BEGIN
    IF to_regclass('public.kyc_profiles') IS NULL THEN
        RETURN NULL;
    END IF;

    EXECUTE 'SELECT status FROM public.kyc_profiles WHERE user_id = $1 LIMIT 1'
        INTO v_status
        USING p_user_id;

    RETURN v_status;
END;
$$;

-- ------------------------------------------------------------------------------
-- 3. LEDGER HELPER (idempotent append-only posting)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_post_ledger(
    p_user_id  TEXT,
    p_type     TEXT,
    p_amount   NUMERIC,
    p_balance_after NUMERIC,
    p_reference TEXT,
    p_description TEXT,
    p_idempotency_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.ledger_entries
        (user_id, type, amount, balance_after, reference_id, description, idempotency_key, created_at)
    VALUES
        (p_user_id, p_type, p_amount, p_balance_after, p_reference, p_description, p_idempotency_key, NOW())
    ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING;
END;
$$;

-- Lock (and lazily create) a wallet row. ALWAYS called before locking trades so
-- concurrent requests serialise in the same order and cannot deadlock.
CREATE OR REPLACE FUNCTION public.fx_lock_wallet(p_user_id TEXT)
RETURNS public.wallets
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_wallet public.wallets;
BEGIN
    SELECT * INTO v_wallet FROM public.wallets
    WHERE user_id = p_user_id AND currency = 'USD' FOR UPDATE;

    IF NOT FOUND THEN
        -- balance 0, never the old 10_000 default.
        INSERT INTO public.wallets (user_id, currency, balance, held_margin)
        VALUES (p_user_id, 'USD', 0, 0)
        ON CONFLICT (user_id, currency) DO NOTHING;

        SELECT * INTO v_wallet FROM public.wallets
        WHERE user_id = p_user_id AND currency = 'USD' FOR UPDATE;
    END IF;

    IF v_wallet.is_frozen THEN
        RAISE EXCEPTION 'WALLET_FROZEN: this account is frozen for trading'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_wallet;
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. ATOMIC CLOSE PRIMITIVE
--
-- The single place any position is ever closed: manual close, SL, TP and
-- stop-out all funnel through here, so the settlement can never diverge.
--
-- `SELECT ... WHERE status='open' FOR UPDATE` is the concurrency guard: the
-- second of two racing closers finds no row and gets 'already_closed' instead of
-- settling the trade twice.
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
    v_wallet   public.wallets;
    v_pnl      NUMERIC;
    v_swap     NUMERIC := 0;
    v_days     INTEGER;
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

    -- Swap: whole days held * lots * per-lot overnight rate for the side.
    IF v_inst.symbol IS NOT NULL THEN
        v_days := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (NOW() - v_t.open_time)) / 86400)::INTEGER);
        v_swap := ROUND(
            v_days * v_t.lots *
            CASE WHEN v_t.side = 'buy' THEN v_inst.swap_long_per_lot ELSE v_inst.swap_short_per_lot END,
            4);
    END IF;

    v_pnl := public.fx_calc_pnl(
        v_t.side, v_t.open_price, p_close_price, v_t.lots, v_t.contract_size,
        COALESCE(p_rate, v_t.quote_to_usd_rate));

    -- Release exactly what this trade reserved, never more than is actually held.
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
            format('Overnight swap on %s for %s day(s)', v_t.symbol, v_days),
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
        'commission', v_t.commission,
        'released_margin', v_release,
        'close_reason', p_reason,
        'trade_status', v_status,
        'new_balance', v_new_bal
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 5. ATOMIC OPEN / PENDING PLACEMENT PRIMITIVE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_activate_trade(
    p_trade_id TEXT,
    p_fill_price NUMERIC,
    p_bid NUMERIC,
    p_ask NUMERIC,
    p_rate NUMERIC,
    p_price_source TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_t       public.trades;
    v_inst    public.instruments;
    v_wallet  public.wallets;
    v_margin  NUMERIC;
    v_comm    NUMERIC := 0;
    v_unreal  NUMERIC;
    v_free    NUMERIC;
    v_new_bal NUMERIC;
BEGIN
    SELECT * INTO v_t FROM public.trades
    WHERE id = p_trade_id AND status = 'pending'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'not_pending', 'trade_id', p_trade_id);
    END IF;

    SELECT * INTO v_inst FROM public.instruments WHERE symbol = v_t.symbol;

    v_margin := public.fx_calc_margin(v_t.lots, v_t.contract_size, p_fill_price, v_t.leverage, p_rate);
    v_comm   := ROUND(COALESCE(v_inst.commission_per_lot, 0) * v_t.lots, 4);

    SELECT * INTO v_wallet FROM public.wallets
    WHERE user_id = v_t.user_id AND currency = 'USD' FOR UPDATE;

    -- Margin is re-validated at TRIGGER time, not at placement time, because the
    -- account may have changed while the order was resting.
    v_unreal := public.fx_unrealized_total(v_t.user_id, NULL);
    v_free   := (COALESCE(v_wallet.balance, 0) + v_unreal) - COALESCE(v_wallet.held_margin, 0);

    IF v_free < (v_margin + v_comm) THEN
        UPDATE public.trades
           SET status = 'rejected',
               reject_reason = format('Insufficient free margin at trigger: need %s, have %s',
                                      ROUND(v_margin + v_comm, 2), ROUND(v_free, 2)),
               updated_at = NOW()
         WHERE id = p_trade_id;

        RETURN jsonb_build_object(
            'status', 'rejected', 'trade_id', p_trade_id,
            'reason', 'INSUFFICIENT_MARGIN',
            'required', v_margin + v_comm, 'available', v_free);
    END IF;

    v_new_bal := COALESCE(v_wallet.balance, 0) - v_comm;

    UPDATE public.wallets
       SET held_margin = held_margin + v_margin,
           balance     = v_new_bal,
           updated_at  = NOW()
     WHERE user_id = v_t.user_id AND currency = 'USD';

    UPDATE public.trades
       SET status            = 'open',
           open_price        = p_fill_price,
           current_price     = p_fill_price,
           open_bid          = p_bid,
           open_ask          = p_ask,
           spread_at_open    = p_ask - p_bid,
           required_margin   = v_margin,
           commission        = v_comm,
           quote_to_usd_rate = COALESCE(p_rate, 1),
           price_source      = p_price_source,
           open_time         = NOW(),
           filled_at         = NOW(),
           updated_at        = NOW()
     WHERE id = p_trade_id;

    PERFORM public.fx_post_ledger(
        v_t.user_id, 'margin_lock', v_margin, v_new_bal, p_trade_id,
        format('Margin locked for %s %s %s lots', v_t.side, v_t.symbol, v_t.lots),
        'margin_lock:' || p_trade_id);

    IF v_comm > 0 THEN
        PERFORM public.fx_post_ledger(
            v_t.user_id, 'commission', -v_comm, v_new_bal, p_trade_id,
            format('Commission on %s', v_t.symbol), 'commission:' || p_trade_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'filled',
        'trade_id', p_trade_id,
        'symbol', v_t.symbol,
        'side', v_t.side,
        'lots', v_t.lots,
        'fill_price', p_fill_price,
        'required_margin', v_margin,
        'commission', v_comm);
END;
$$;
