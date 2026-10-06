-- ==============================================================================
-- ASIANFX MARKET MAKER TRADING ENGINE: SUPABASE DATABASE SCHEMA & PROCEDURES
-- ==============================================================================
--
--  ####  SUPERSEDED — DO NOT RUN THIS FILE AGAINST A LIVE DATABASE  ####
--
--  Kept only as a record of the original bootstrap. Re-running it would REVERSE
--  the security fixes in supabase/migrations/20261001*, because the versions
--  below still contain:
--
--   * wallets.balance DEFAULT 10000  -> every new wallet mints $10,000
--   * `FOR ALL USING (auth.uid() = user_id)` on wallets / trades /
--     ledger_entries -> a signed-in user can UPDATE their own balance, flip a
--     trade to 'closed', or INSERT fabricated ledger rows directly from Flutter
--   * rpc_open_trade falling back to the hard-coded user
--     'usr_institutional_01' when auth.uid() is NULL, and creating $10,000
--     wallets on demand
--   * rpc_close_trade taking p_close_price FROM THE CLIENT and never checking
--     trade ownership -> any caller could close anyone's position at any price
--
--  The authoritative schema now lives in, and must be applied in this order:
--    supabase/migrations/20261001000000_trading_core_schema.sql
--    supabase/migrations/20261001000100_trading_rpcs.sql
--    supabase/migrations/20261001000200_trading_public_rpcs.sql
--
--  Those migrations are additive and idempotent: they ALTER the tables defined
--  here, drop the permissive policies, and drop every old rpc_open_trade /
--  rpc_close_trade overload by name.
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

-- ------------------------------------------------------------------------------
-- 8. INSTITUTIONAL KYC & AML VERIFICATION MODULE (SUPABASE SCHEMA)
-- ------------------------------------------------------------------------------

-- 8.1 KYC Profiles Table (Primary User Verification Lifecycle)
CREATE TABLE IF NOT EXISTS public.kyc_profiles (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    first_name TEXT NOT NULL,
    middle_name TEXT,
    last_name TEXT NOT NULL,
    date_of_birth TIMESTAMP WITH TIME ZONE,
    nationality TEXT NOT NULL DEFAULT 'Pakistan',
    country_of_residence TEXT NOT NULL DEFAULT 'Pakistan',
    address TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'NOT_STARTED', -- NOT_STARTED, IN_PROGRESS, PENDING_REVIEW, MANUAL_REVIEW, APPROVED, REJECTED, RESUBMISSION_REQUIRED
    rejection_reason TEXT,
    resubmission_notes TEXT,
    document_number TEXT,
    identity_doc_type VARCHAR(32) DEFAULT 'CNIC',
    address_doc_type VARCHAR(32) DEFAULT 'UTILITY_BILL',
    submitted_at TIMESTAMP WITH TIME ZONE,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kyc_profiles_user_id ON public.kyc_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_profiles_status ON public.kyc_profiles(status);

-- 8.2 KYC Documents Table (Government ID, Selfie/Liveness, Proof of Address)
CREATE TABLE IF NOT EXISTS public.kyc_documents (
    id TEXT PRIMARY KEY,
    kyc_id TEXT NOT NULL REFERENCES public.kyc_profiles(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    document_category VARCHAR(32) NOT NULL, -- IDENTITY, ADDRESS
    document_type VARCHAR(32) NOT NULL,     -- CNIC, PASSPORT, DRIVERS_LICENSE, UTILITY_BILL, BANK_STATEMENT
    storage_path TEXT,
    original_file_name TEXT NOT NULL,
    mime_type VARCHAR(64) NOT NULL DEFAULT 'image/jpeg',
    file_size BIGINT NOT NULL DEFAULT 0,
    document_side VARCHAR(16) DEFAULT 'SINGLE', -- FRONT, BACK, SINGLE
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING_REVIEW',
    rejection_reason TEXT,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_kyc_documents_kyc_id ON public.kyc_documents(kyc_id);
CREATE INDEX IF NOT EXISTS idx_kyc_documents_user_id ON public.kyc_documents(user_id);

-- 8.3 KYC Audit Logs Table (Append-Only Immutable Compliance History)
CREATE TABLE IF NOT EXISTS public.kyc_audit_logs (
    id TEXT PRIMARY KEY,
    kyc_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    action VARCHAR(64) NOT NULL, -- SUBMITTED, DOCUMENT_UPLOADED, APPROVED, REJECTED, RESUBMISSION_REQUESTED
    performed_by TEXT NOT NULL DEFAULT 'SYSTEM',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_kyc_audit_logs_kyc_id ON public.kyc_audit_logs(kyc_id);
CREATE INDEX IF NOT EXISTS idx_kyc_audit_logs_user_id ON public.kyc_audit_logs(user_id);

-- 8.4 Row Level Security (RLS) for KYC Tables
ALTER TABLE public.kyc_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_audit_logs ENABLE ROW LEVEL SECURITY;

-- Profiles: Users can view their own profile; admins can view all
DROP POLICY IF EXISTS "Users can view own kyc profile" ON public.kyc_profiles;
CREATE POLICY "Users can view own kyc profile" ON public.kyc_profiles
    FOR SELECT USING (auth.uid()::text = user_id::text OR auth.jwt() ->> 'role' = 'admin' OR auth.jwt() ->> 'role' = 'superadmin');

-- Profiles: Users can insert/upsert their own profile
DROP POLICY IF EXISTS "Users can insert own kyc profile" ON public.kyc_profiles;
CREATE POLICY "Users can insert own kyc profile" ON public.kyc_profiles
    FOR INSERT WITH CHECK (auth.uid()::text = user_id::text);

-- Profiles: Users can update their own profile; compliance officers/admins can update all
DROP POLICY IF EXISTS "Users and admins can update kyc profile" ON public.kyc_profiles;
CREATE POLICY "Users and admins can update kyc profile" ON public.kyc_profiles
    FOR UPDATE USING (
        auth.uid()::text = user_id::text OR 
        auth.jwt() ->> 'role' = 'admin' OR 
        auth.jwt() ->> 'role' = 'superadmin'
    );

-- Documents: Users can view and upload their own documents; admins view all
DROP POLICY IF EXISTS "Users can view own kyc documents" ON public.kyc_documents;
CREATE POLICY "Users can view own kyc documents" ON public.kyc_documents
    FOR SELECT USING (auth.uid()::text = user_id::text OR auth.jwt() ->> 'role' = 'admin');

DROP POLICY IF EXISTS "Users can insert own kyc documents" ON public.kyc_documents;
CREATE POLICY "Users can insert own kyc documents" ON public.kyc_documents
    FOR INSERT WITH CHECK (auth.uid()::text = user_id::text);

DROP POLICY IF EXISTS "Admins can update kyc documents" ON public.kyc_documents;
CREATE POLICY "Admins can update kyc documents" ON public.kyc_documents
    FOR UPDATE USING (auth.jwt() ->> 'role' = 'admin');

-- Audit Logs: Append-only for users & admins
DROP POLICY IF EXISTS "Users and system can view audit logs" ON public.kyc_audit_logs;
CREATE POLICY "Users and system can view audit logs" ON public.kyc_audit_logs
    FOR SELECT USING (auth.uid()::text = user_id::text OR auth.jwt() ->> 'role' = 'admin');

DROP POLICY IF EXISTS "Users and system can insert audit logs" ON public.kyc_audit_logs;
CREATE POLICY "Users and system can insert audit logs" ON public.kyc_audit_logs
    FOR INSERT WITH CHECK (auth.uid()::text = user_id::text OR auth.jwt() ->> 'role' = 'admin');

-- 8.5 Storage Bucket Configuration for kyc-documents (Private Bucket)
INSERT INTO storage.buckets (id, name, public)
VALUES ('kyc-documents', 'kyc-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: Users can upload and read their own documents in kyc-documents bucket
DROP POLICY IF EXISTS "Users can upload their own KYC docs" ON storage.objects;
CREATE POLICY "Users can upload their own KYC docs" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'kyc-documents' AND (
            (storage.foldername(name))[1] = auth.uid()::text OR
            auth.uid() IS NOT NULL
        )
    );

DROP POLICY IF EXISTS "Users and admins can view KYC docs" ON storage.objects;
CREATE POLICY "Users and admins can view KYC docs" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'kyc-documents' AND (
            (storage.foldername(name))[1] = auth.uid()::text OR
            auth.jwt() ->> 'role' = 'admin'
        )
    );

-- 8.6 Enable Realtime for kyc_profiles
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.kyc_profiles;
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

-- ------------------------------------------------------------------------------
-- 9. DEPOSITS TABLE & ATOMIC SETTLEMENT FOR USDT TRC-20
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deposits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,
    txid VARCHAR(128) NOT NULL,
    amount NUMERIC(18, 4) NOT NULL CHECK (amount > 0),
    token VARCHAR(20) NOT NULL DEFAULT 'USDT',
    network VARCHAR(20) NOT NULL DEFAULT 'TRC20',
    deposit_address TEXT NOT NULL,
    from_address TEXT,
    block_number BIGINT,
    status VARCHAR(30) NOT NULL DEFAULT 'CONFIRMED' CHECK (status IN ('PENDING', 'CONFIRMED', 'REJECTED')),
    raw_tx_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_deposit_txid UNIQUE (txid)
);

CREATE INDEX IF NOT EXISTS idx_deposits_user_id ON public.deposits(user_id);
CREATE INDEX IF NOT EXISTS idx_deposits_txid ON public.deposits(txid);
CREATE INDEX IF NOT EXISTS idx_deposits_status ON public.deposits(status);

ALTER TABLE public.deposits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own deposits" ON public.deposits;
CREATE POLICY "Users can view own deposits" ON public.deposits
    FOR SELECT USING (auth.uid()::text = user_id::text);

DROP POLICY IF EXISTS "Service role manages deposits" ON public.deposits;
CREATE POLICY "Service role manages deposits" ON public.deposits
    FOR ALL USING (auth.role() = 'service_role');

-- Atomic double-credit prevention & wallet balance update procedure
CREATE OR REPLACE FUNCTION public.credit_verified_deposit(
    p_user_id TEXT,
    p_txid VARCHAR,
    p_amount NUMERIC,
    p_token VARCHAR DEFAULT 'USDT',
    p_network VARCHAR DEFAULT 'TRC20',
    p_deposit_address TEXT DEFAULT '',
    p_from_address TEXT DEFAULT NULL,
    p_block_number BIGINT DEFAULT NULL,
    p_raw_tx JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_txid VARCHAR(128);
    v_current_balance NUMERIC(18, 4);
    v_new_balance NUMERIC(18, 4);
    v_deposit_id UUID;
BEGIN
    v_clean_txid := LOWER(TRIM(p_txid));

    -- 1. Check if TXID has already been credited
    IF EXISTS (SELECT 1 FROM public.deposits WHERE txid = v_clean_txid) THEN
        RETURN jsonb_build_object(
            'success', false,
            'verified', false,
            'already_credited', true,
            'message', 'This transaction ID has already been credited to an account.'
        );
    END IF;

    -- 2. Validate Amount
    IF p_amount <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'verified', false,
            'already_credited', false,
            'message', 'Deposit amount must be strictly greater than zero.'
        );
    END IF;

    -- 3. Insert Deposit Record with unique constraint protection
    BEGIN
        INSERT INTO public.deposits (
            user_id,
            txid,
            amount,
            token,
            network,
            deposit_address,
            from_address,
            block_number,
            status,
            raw_tx_data,
            created_at,
            updated_at
        ) VALUES (
            p_user_id,
            v_clean_txid,
            p_amount,
            UPPER(p_token),
            UPPER(p_network),
            p_deposit_address,
            p_from_address,
            p_block_number,
            'CONFIRMED',
            p_raw_tx,
            NOW(),
            NOW()
        )
        RETURNING id INTO v_deposit_id;
    EXCEPTION
        WHEN unique_violation THEN
            RETURN jsonb_build_object(
                'success', false,
                'verified', false,
                'already_credited', true,
                'message', 'This transaction ID has already been credited to an account.'
            );
    END;

    -- 4. Ensure User Wallet Exists
    INSERT INTO public.wallets (
        user_id,
        currency,
        balance,
        held_margin,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        'USD',
        0.0000,
        0.0000,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, currency) DO NOTHING;

    -- 5. Lock Wallet Row (FOR UPDATE)
    SELECT balance INTO v_current_balance
    FROM public.wallets
    WHERE user_id = p_user_id AND currency = 'USD'
    FOR UPDATE;

    v_new_balance := v_current_balance + p_amount;

    -- 6. Update Realized Liquid Balance
    UPDATE public.wallets
    SET balance = v_new_balance,
        updated_at = NOW()
    WHERE user_id = p_user_id AND currency = 'USD';

    -- 7. Record Immutable Ledger Audit Entry
    INSERT INTO public.ledger_entries (
        user_id,
        type,
        amount,
        balance_after,
        reference_id,
        description,
        created_at
    ) VALUES (
        p_user_id,
        'deposit',
        p_amount,
        v_new_balance,
        v_clean_txid,
        format('USDT TRC20 Deposit verified via Tatum Mainnet API (Block #%s)', COALESCE(p_block_number::text, 'N/A')),
        NOW()
    );

    -- 8. Return Atomic Success Result
    RETURN jsonb_build_object(
        'success', true,
        'verified', true,
        'already_credited', false,
        'deposit_id', v_deposit_id,
        'txid', v_clean_txid,
        'amount_credited', p_amount,
        'previous_balance', v_current_balance,
        'new_balance', v_new_balance,
        'message', 'Deposit verified and balance credited successfully'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.credit_verified_deposit FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.credit_verified_deposit TO service_role;
