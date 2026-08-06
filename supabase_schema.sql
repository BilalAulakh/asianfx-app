-- FXAsianApp Supabase PostgreSQL Database Schema
-- Copy and paste this script into your Supabase Dashboard -> SQL Editor and click 'Run'.

-- 1. Create Enums
CREATE TYPE user_role AS ENUM ('USER', 'ADMIN', 'SUPERADMIN');
CREATE TYPE kyc_status AS ENUM ('UNVERIFIED', 'PENDING', 'APPROVED', 'REJECTED');
CREATE TYPE order_side AS ENUM ('BUY', 'SELL');
CREATE TYPE order_type AS ENUM ('MARKET', 'LIMIT', 'STOP');
CREATE TYPE order_status AS ENUM ('PENDING', 'OPEN', 'CLOSED', 'CANCELLED');

-- 2. Profiles / Users Table (Linked to auth.users if using Supabase Auth)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    role user_role DEFAULT 'USER',
    kyc_status kyc_status DEFAULT 'UNVERIFIED',
    is_two_factor_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. KYC Documents Table
CREATE TABLE public.kyc_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL,
    document_url TEXT NOT NULL,
    status kyc_status DEFAULT 'PENDING',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Trading Accounts Table
CREATE TABLE public.trading_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    account_type TEXT DEFAULT 'STANDARD',
    leverage DOUBLE PRECISION DEFAULT 100.0,
    balance DOUBLE PRECISION DEFAULT 10000.0,
    equity DOUBLE PRECISION DEFAULT 10000.0,
    margin DOUBLE PRECISION DEFAULT 0.0,
    free_margin DOUBLE PRECISION DEFAULT 10000.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Open/Closed Positions Table
CREATE TABLE public.positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES public.trading_accounts(id) ON DELETE CASCADE,
    symbol TEXT NOT NULL,
    side order_side NOT NULL,
    type order_type NOT NULL,
    status order_status DEFAULT 'OPEN',
    lot_size DOUBLE PRECISION NOT NULL,
    open_price DOUBLE PRECISION NOT NULL,
    close_price DOUBLE PRECISION,
    stop_loss DOUBLE PRECISION,
    take_profit DOUBLE PRECISION,
    floating_pl DOUBLE PRECISION DEFAULT 0.0,
    open_time TIMESTAMPTZ DEFAULT NOW(),
    close_time TIMESTAMPTZ
);

-- 6. Wallets Table
CREATE TABLE public.wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    currency TEXT DEFAULT 'USD',
    balance DOUBLE PRECISION DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Transactions Table (Deposits / Withdrawals)
CREATE TABLE public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES public.wallets(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- DEPOSIT, WITHDRAWAL, TRANSFER
    amount DOUBLE PRECISION NOT NULL,
    status TEXT DEFAULT 'PENDING',
    method TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trading_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
