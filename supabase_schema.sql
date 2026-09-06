-- ==============================================================================
-- ASIANFX MARKET MAKER TRADING ENGINE: SUPABASE DATABASE SCHEMA & PROCEDURES
-- ==============================================================================

-- Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. WALLETS TABLE (Double-Entry Balance & Hold State)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    balance NUMERIC(18, 4) NOT NULL DEFAULT 10000.0000,       -- Realized Liquid Cash
    held_margin NUMERIC(18, 4) NOT NULL DEFAULT 0.0000,      -- Locked margin in open trades
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_user_wallet UNIQUE (user_id, currency)
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);

-- ------------------------------------------------------------------------------
-- 2. TRADES TABLE (Positions & Orders)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.trades (
    id VARCHAR(64) PRIMARY KEY,
    user_id TEXT NOT NULL,
    order_id VARCHAR(64) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    side VARCHAR(10) NOT NULL CHECK (side IN ('buy', 'sell')),
    type VARCHAR(20) NOT NULL DEFAULT 'market',
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'cancelled', 'pending', 'liquidated')),
    lots NUMERIC(14, 4) NOT NULL,
    contract_size NUMERIC(14, 4) NOT NULL,
    open_price NUMERIC(18, 5) NOT NULL,
    current_price NUMERIC(18, 5),
    close_price NUMERIC(18, 5),
    target_price NUMERIC(18, 5),
    stop_loss NUMERIC(18, 5),
    take_profit NUMERIC(18, 5),
    required_margin NUMERIC(18, 4) NOT NULL,
    leverage NUMERIC(10, 2) NOT NULL DEFAULT 100.00,
    unrealized_pnl NUMERIC(18, 4) DEFAULT 0.0000,
    realized_pnl NUMERIC(18, 4) DEFAULT 0.0000,
    open_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    close_time TIMESTAMP WITH TIME ZONE,
    close_reason VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trades_user_status ON public.trades(user_id, status);
CREATE INDEX IF NOT EXISTS idx_trades_symbol ON public.trades(symbol);

-- ------------------------------------------------------------------------------
-- 3. LEDGER ENTRIES TABLE (Immutable Audit Trail)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,
    type VARCHAR(30) NOT NULL,
    amount NUMERIC(18, 4) NOT NULL,
    balance_after NUMERIC(18, 4) NOT NULL,
    reference_id VARCHAR(64),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ledger_user_id ON public.ledger_entries(user_id);

-- ------------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS Policies with explicit text casting)
-- ------------------------------------------------------------------------------
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
CREATE POLICY "Users can view own wallet" ON public.wallets
    FOR ALL USING (auth.uid()::text = user_id::text);

DROP POLICY IF EXISTS "Users can view own trades" ON public.trades;
CREATE POLICY "Users can view own trades" ON public.trades
    FOR ALL USING (auth.uid()::text = user_id::text);

DROP POLICY IF EXISTS "Users can view own ledger" ON public.ledger_entries;
CREATE POLICY "Users can view own ledger" ON public.ledger_entries
    FOR ALL USING (auth.uid()::text = user_id::text);

-- ------------------------------------------------------------------------------
-- 5. ATOMIC RPC FUNCTION: rpc_open_trade (Margin Check & Lock)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_open_trade(
    p_trade_id VARCHAR,
    p_order_id VARCHAR,
    p_symbol VARCHAR,
    p_side VARCHAR,
    p_lots NUMERIC,
    p_contract_size NUMERIC,
    p_open_price NUMERIC,
    p_leverage NUMERIC DEFAULT 100.0,
    p_stop_loss NUMERIC DEFAULT NULL,
    p_take_profit NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id TEXT := COALESCE(auth.uid()::text, 'usr_institutional_01');
    v_wallet RECORD;
    v_req_margin NUMERIC(18, 4);
    v_free_margin NUMERIC(18, 4);
BEGIN
    -- Calculate Required Margin = (Lots * Contract Size * Open Price) / Leverage
    v_req_margin := ROUND((p_lots * p_contract_size * p_open_price) / p_leverage, 4);

    -- Lock the wallet row for update
    SELECT * INTO v_wallet FROM public.wallets 
    WHERE user_id = v_user_id AND currency = 'USD' 
    FOR UPDATE;

    -- If wallet doesn't exist, create an initial one
    IF NOT FOUND THEN
        INSERT INTO public.wallets (user_id, currency, balance, held_margin)
        VALUES (v_user_id, 'USD', 10000.0000, 0.0000)
        RETURNING * INTO v_wallet;
    END IF;

    -- Calculate Free Margin (Balance - Held Margin)
    v_free_margin := v_wallet.balance - v_wallet.held_margin;

    -- Verify Margin Sufficiency
    IF v_free_margin < v_req_margin THEN
        RAISE EXCEPTION 'Insufficient Free Margin. Available: %, Required: %', v_free_margin, v_req_margin;
    END IF;

    -- Atomically lock the margin
    UPDATE public.wallets
    SET held_margin = held_margin + v_req_margin,
        updated_at = NOW()
    WHERE id = v_wallet.id;

    -- Insert Trade
    INSERT INTO public.trades (
        id, user_id, order_id, symbol, side, type, status,
        lots, contract_size, open_price, current_price,
        stop_loss, take_profit, required_margin, leverage,
        open_time
    ) VALUES (
        p_trade_id, v_user_id, p_order_id, p_symbol, p_side, 'market', 'open',
        p_lots, p_contract_size, p_open_price, p_open_price,
        p_stop_loss, p_take_profit, v_req_margin, p_leverage,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        current_price = p_open_price,
        status = 'open',
        updated_at = NOW();

    -- Record in Ledger
    INSERT INTO public.ledger_entries (user_id, type, amount, balance_after, reference_id, description)
    VALUES (v_user_id, 'margin_lock', v_req_margin, v_wallet.balance, p_trade_id, 'Margin hold for trade ' || p_symbol);

    RETURN jsonb_build_object(
        'status', 'success',
        'trade_id', p_trade_id,
        'held_margin', v_req_margin,
        'remaining_free_margin', (v_free_margin - v_req_margin)
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 6. ATOMIC RPC FUNCTION: rpc_close_trade (PnL Settlement & Margin Release)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_close_trade(
    p_trade_id VARCHAR,
    p_close_price NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id TEXT := COALESCE(auth.uid()::text, 'usr_institutional_01');
    v_trade RECORD;
    v_wallet RECORD;
    v_realized_pnl NUMERIC(18, 4);
    v_price_diff NUMERIC(18, 5);
BEGIN
    -- Lock trade record
    SELECT * INTO v_trade FROM public.trades
    WHERE id = p_trade_id AND status = 'open'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'status', 'skipped',
            'message', 'Trade not open or already closed'
        );
    END IF;

    -- Lock wallet record
    SELECT * INTO v_wallet FROM public.wallets
    WHERE user_id = v_trade.user_id AND currency = 'USD'
    FOR UPDATE;

    -- Calculate Realized PnL:
    -- Buy: (Close - Open) * Lots * ContractSize
    -- Sell: (Open - Close) * Lots * ContractSize
    IF v_trade.side = 'buy' THEN
        v_price_diff := p_close_price - v_trade.open_price;
    ELSE
        v_price_diff := v_trade.open_price - p_close_price;
    END IF;

    v_realized_pnl := ROUND(v_price_diff * v_trade.lots * v_trade.contract_size, 4);

    -- Settle in Wallet:
    -- 1. Release held margin: held_margin = held_margin - required_margin
    -- 2. Apply realized PnL: balance = balance + realized_pnl
    IF v_wallet.id IS NOT NULL THEN
        UPDATE public.wallets
        SET held_margin = GREATEST(0.0000, held_margin - v_trade.required_margin),
            balance = balance + v_realized_pnl,
            updated_at = NOW()
        WHERE id = v_wallet.id;
    END IF;

    -- Update Trade Status to Closed
    UPDATE public.trades
    SET status = 'closed',
        close_price = p_close_price,
        current_price = p_close_price,
        realized_pnl = v_realized_pnl,
        unrealized_pnl = 0.0000,
        close_time = NOW(),
        updated_at = NOW()
    WHERE id = p_trade_id;

    -- Record Realized PnL in Ledger
    INSERT INTO public.ledger_entries (user_id, type, amount, balance_after, reference_id, description)
    VALUES (v_trade.user_id, 'realized_pnl', v_realized_pnl, COALESCE(v_wallet.balance + v_realized_pnl, 10000.0), p_trade_id, 'Closed ' || v_trade.symbol || ' trade with PnL');

    RETURN jsonb_build_object(
        'status', 'success',
        'trade_id', p_trade_id,
        'realized_pnl', v_realized_pnl,
        'released_margin', v_trade.required_margin,
        'new_balance', COALESCE(v_wallet.balance + v_realized_pnl, 10000.0)
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. ENABLE REALTIME PUBLICATION (Safely check if already added)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.trades;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;
