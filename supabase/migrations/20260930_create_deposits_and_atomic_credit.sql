-- ==============================================================================
-- MIGRATION: 20260930_create_deposits_and_atomic_credit.sql
-- TRON USDT TRC-20 Real-Money Deposit Pipeline with Atomic Idempotent Settlement
-- ==============================================================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. DEPOSITS TABLE
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

-- Fast lookup indexes
CREATE INDEX IF NOT EXISTS idx_deposits_user_id ON public.deposits(user_id);
CREATE INDEX IF NOT EXISTS idx_deposits_txid ON public.deposits(txid);
CREATE INDEX IF NOT EXISTS idx_deposits_status ON public.deposits(status);

-- ------------------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY (RLS) FOR DEPOSITS TABLE
-- ------------------------------------------------------------------------------
ALTER TABLE public.deposits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own deposits" ON public.deposits;
CREATE POLICY "Users can view own deposits" ON public.deposits
    FOR SELECT USING (auth.uid()::text = user_id::text);

-- Direct client INSERT/UPDATE is prohibited (settlement only occurs through Edge Function / RPC)
DROP POLICY IF EXISTS "Service role manages deposits" ON public.deposits;
CREATE POLICY "Service role manages deposits" ON public.deposits
    FOR ALL USING (auth.role() = 'service_role');

-- ------------------------------------------------------------------------------
-- 3. ATOMIC RPC FUNCTION: credit_verified_deposit
-- ------------------------------------------------------------------------------
-- Guarantees double-credit prevention, strict row locking, and immutable audit log.
-- Executed with SECURITY DEFINER so it can safely credit balances post-verification.
-- ------------------------------------------------------------------------------
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

    -- Step 1: Check if TXID has already been credited
    IF EXISTS (SELECT 1 FROM public.deposits WHERE txid = v_clean_txid) THEN
        RETURN jsonb_build_object(
            'success', false,
            'verified', false,
            'already_credited', true,
            'message', 'This transaction ID has already been credited to an account.'
        );
    END IF;

    -- Step 2: Validate Amount
    IF p_amount <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'verified', false,
            'already_credited', false,
            'message', 'Deposit amount must be strictly greater than zero.'
        );
    END IF;

    -- Step 3: Insert Deposit Record (Protected by UNIQUE constraint)
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
            -- Concurrent duplicate transaction attempt caught cleanly
            RETURN jsonb_build_object(
                'success', false,
                'verified', false,
                'already_credited', true,
                'message', 'This transaction ID has already been credited to an account.'
            );
    END;

    -- Step 4: Ensure User Wallet Exists
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

    -- Step 5: Lock Wallet Row (FOR UPDATE) to Prevent Concurrency Drift
    SELECT balance INTO v_current_balance
    FROM public.wallets
    WHERE user_id = p_user_id AND currency = 'USD'
    FOR UPDATE;

    v_new_balance := v_current_balance + p_amount;

    -- Step 6: Update Realized Liquid Balance
    UPDATE public.wallets
    SET balance = v_new_balance,
        updated_at = NOW()
    WHERE user_id = p_user_id AND currency = 'USD';

    -- Step 7: Record Immutable Ledger Audit Entry
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

    -- Step 8: Return Atomic Success Result
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

-- Grant execution to service_role (Edge Functions use Service Role key)
REVOKE ALL ON FUNCTION public.credit_verified_deposit FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.credit_verified_deposit TO service_role;
