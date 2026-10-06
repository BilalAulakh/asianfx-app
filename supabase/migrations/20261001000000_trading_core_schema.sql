-- ==============================================================================
-- MIGRATION: 20261001000000_trading_core_schema.sql
--
-- Makes the DATABASE the single authority for trading money state.
--
-- This migration is additive and idempotent:
--   * no table is dropped, no production row is deleted
--   * every column is added with ADD COLUMN IF NOT EXISTS
--   * the pre-existing `trades` / `wallets` / `ledger_entries` tables are reused
--     (pending orders live in `trades` with status='pending', as they already did)
--
-- What it fixes:
--   1. wallets.balance defaulted to 10000 -> every new wallet minted $10k.
--   2. RLS used `FOR ALL USING (auth.uid() = user_id)` on wallets/trades/
--      ledger_entries, so any logged-in user could UPDATE their own balance,
--      flip a trade to 'closed', or fabricate ledger rows straight from Flutter.
--   3. There was no instrument specification anywhere in the DB, so the server
--      could not independently validate lots/leverage/margin.
--   4. Nothing recorded commission, swap, the requested vs filled price, or the
--      quote->USD conversion rate, so a fill could not be audited.
--   5. Nothing prevented a retried request from opening two trades.
-- ==============================================================================

-- NOTE: gen_random_uuid() (PostgreSQL core, pg_catalog) is used throughout
-- instead of uuid_generate_v4(). On Supabase the uuid-ossp extension lives in
-- the `extensions` schema, which is NOT on the `SET search_path = public` these
-- SECURITY DEFINER functions pin — so uuid_generate_v4() resolved at CREATE
-- TABLE time but failed at run time with "function uuid_generate_v4() does not
-- exist" the moment an RPC tried to call it.

-- Repoint every public column DEFAULT that still names uuid_generate_v4(), and
-- leave a shim for the bare name. Column defaults inherited from the original
-- supabase_schema.sql call it, and anything resolving it under
-- `SET search_path = public` fails at run time with
-- "function uuid_generate_v4() does not exist".
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema = 'public'
          AND c.column_default ILIKE '%uuid_generate_v4%'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.%I ALTER COLUMN %I SET DEFAULT gen_random_uuid()',
            r.table_name, r.column_name);
    END LOOP;
END $$;

-- gen_random_uuid() also produces a v4 UUID, so this shim is behaviourally
-- identical for any caller that still uses the uuid-ossp name.
CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql VOLATILE PARALLEL SAFE
AS $$ SELECT gen_random_uuid() $$;

GRANT EXECUTE ON FUNCTION public.uuid_generate_v4() TO authenticated, anon, service_role;

-- ------------------------------------------------------------------------------
-- 0. AUTHORIZATION HELPERS (defined first: the RLS policies below call them)
-- ------------------------------------------------------------------------------

-- The calling user's id, or NULL for service_role / unauthenticated calls.
CREATE OR REPLACE FUNCTION public.fx_auth_user_id()
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path = public, auth
AS $$ SELECT NULLIF(auth.uid()::text, '') $$;

-- Same, but hard-fails. Every user-facing financial RPC starts with this so a
-- request can never fall back to a hard-coded "institutional" account the way
-- the old rpc_open_trade did (`COALESCE(auth.uid()::text, 'usr_institutional_01')`).
CREATE OR REPLACE FUNCTION public.fx_require_user_id()
RETURNS TEXT
LANGUAGE plpgsql STABLE
SET search_path = public, auth
AS $$
DECLARE v_uid TEXT := public.fx_auth_user_id();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: a signed-in session is required for this operation'
            USING ERRCODE = '28000';
    END IF;
    RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.fx_is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = public, auth
AS $$
    SELECT COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
        OR COALESCE(auth.jwt() ->> 'role', '') IN ('admin', 'superadmin')
        OR COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') IN ('admin', 'superadmin')
        OR COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') IN ('admin', 'superadmin');
$$;

-- TRUE for trusted backend callers: the service_role key, or a direct database
-- connection with no JWT at all (pg_cron / psql).
--
-- `session_user` is deliberate: inside a SECURITY DEFINER function `current_user`
-- is the function owner (postgres) for EVERY caller, so using it here would make
-- every authenticated client an administrator.
CREATE OR REPLACE FUNCTION public.fx_is_backend()
RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = public, auth
AS $$
    SELECT COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
        OR (auth.jwt() IS NULL AND session_user IN ('postgres', 'supabase_admin'));
$$;

CREATE OR REPLACE FUNCTION public.fx_require_admin()
RETURNS TEXT
LANGUAGE plpgsql STABLE
SET search_path = public, auth
AS $$
BEGIN
    IF NOT (public.fx_is_admin() OR public.fx_is_backend()) THEN
        RAISE EXCEPTION 'FORBIDDEN: administrator privileges are required'
            USING ERRCODE = '42501';
    END IF;
    RETURN COALESCE(public.fx_auth_user_id(), 'system:' || session_user);
END;
$$;

-- ------------------------------------------------------------------------------
-- 1. BROKER CONFIGURATION (single row)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.broker_config (
    id                       SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    account_currency         VARCHAR(10)   NOT NULL DEFAULT 'USD',
    margin_call_level_pct    NUMERIC(8, 2) NOT NULL DEFAULT 50.00,
    stop_out_level_pct       NUMERIC(8, 2) NOT NULL DEFAULT 10.00,
    -- Maximum liquidation passes in one evaluation cycle (runaway-cascade guard).
    max_liquidation_passes   SMALLINT      NOT NULL DEFAULT 20,
    -- A quote written by the price publisher is authoritative for this long.
    quote_max_age_seconds    INTEGER       NOT NULL DEFAULT 60,
    -- How far a client-submitted quote may deviate from the last known price
    -- before the request is rejected (fraction, 0.02 = 2%).
    quote_band_fraction      NUMERIC(8, 6) NOT NULL DEFAULT 0.020000,
    -- Maximum slippage tolerated between the price the user saw and the fill.
    max_slippage_fraction    NUMERIC(8, 6) NOT NULL DEFAULT 0.010000,
    allow_client_quotes      BOOLEAN       NOT NULL DEFAULT TRUE,
    -- Defaults to FALSE to preserve the app's current KycPolicy.canTrade rule
    -- (tier-0 users may trade). Flip to TRUE to enforce APPROVED KYC in the DB.
    require_kyc_for_trading  BOOLEAN       NOT NULL DEFAULT FALSE,
    require_kyc_for_withdraw BOOLEAN       NOT NULL DEFAULT TRUE,
    updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

INSERT INTO public.broker_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 2. INSTRUMENT SPECIFICATIONS
--    The authoritative contract model. Both Flutter (display) and the RPCs
--    (execution) must agree on these numbers.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.instruments (
    symbol                VARCHAR(20) PRIMARY KEY,
    name                  TEXT          NOT NULL,
    category              VARCHAR(20)   NOT NULL,
    base_currency         VARCHAR(12)   NOT NULL,
    -- PnL and notional are denominated in this currency before FX conversion.
    quote_currency        VARCHAR(12)   NOT NULL DEFAULT 'USD',
    contract_size         NUMERIC(18, 6) NOT NULL,
    digits                SMALLINT      NOT NULL DEFAULT 2,
    -- One quoted price point = 10^-digits. Stored so SQL never re-derives it.
    point_size            NUMERIC(18, 8) NOT NULL,
    spread_markup_points  INTEGER       NOT NULL DEFAULT 15,
    min_lots              NUMERIC(14, 4) NOT NULL DEFAULT 0.01,
    max_lots              NUMERIC(14, 4) NOT NULL DEFAULT 100,
    lot_step              NUMERIC(14, 4) NOT NULL DEFAULT 0.01,
    max_leverage          NUMERIC(10, 2) NOT NULL DEFAULT 500,
    commission_per_lot    NUMERIC(18, 4) NOT NULL DEFAULT 0,
    swap_long_per_lot     NUMERIC(18, 4) NOT NULL DEFAULT 0,
    swap_short_per_lot    NUMERIC(18, 4) NOT NULL DEFAULT 0,
    trading_enabled       BOOLEAN       NOT NULL DEFAULT TRUE,
    -- NULL = 24/7. Otherwise UTC minutes-of-week ranges may be added later.
    trading_hours         JSONB,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- 2b. SEED the 68 instruments the Flutter feed already offers.
--     Values are transcribed from MarketFeedService._addInst / _spreadMarkupMap
--     and AppConstants contract sizes, so client and server agree exactly.
--     ON CONFLICT DO NOTHING: re-running never overwrites dealer edits.
INSERT INTO public.instruments (
    symbol, name, category, base_currency, quote_currency, contract_size, digits,
    spread_markup_points, min_lots, max_lots, lot_step, max_leverage, point_size
)
SELECT v.symbol, v.name, v.category, v.base_currency, v.quote_currency,
       v.contract_size, v.digits, v.spread_markup_points,
       v.min_lots, v.max_lots, v.lot_step, v.max_leverage,
       POWER(10::NUMERIC, (-1 * v.digits)::NUMERIC)
FROM (VALUES
  ('EUR/USD', 'Euro vs US Dollar', 'forex', 'EUR', 'USD', 100000, 4, 12, 0.01, 100, 0.01, 500, 1.1633, 1.1635),
  ('GBP/USD', 'British Pound vs US Dollar', 'forex', 'GBP', 'USD', 100000, 4, 15, 0.01, 100, 0.01, 500, 1.3549, 1.3552),
  ('USD/JPY', 'US Dollar vs Japanese Yen', 'forex', 'USD', 'JPY', 100000, 2, 14, 0.01, 100, 0.01, 500, 153.59, 153.62),
  ('XAU/USD', 'Gold vs US Dollar', 'forex', 'XAU', 'USD', 100, 2, 15, 0.01, 100, 0.01, 500, 4192.04, 4192.44),
  ('XAG/USD', 'Silver vs US Dollar', 'forex', 'XAG', 'USD', 5000, 2, 3, 0.01, 100, 0.01, 500, 63.78, 63.81),
  ('XPT/USD', 'Platinum vs US Dollar', 'forex', 'XPT', 'USD', 100, 2, 25, 0.01, 100, 0.01, 500, 1045.60, 1046.20),
  ('USD/CHF', 'US Dollar vs Swiss Franc', 'forex', 'USD', 'CHF', 100000, 4, 15, 0.01, 100, 0.01, 500, 0.8095, 0.8098),
  ('AUD/USD', 'Australian Dollar vs US Dollar', 'forex', 'AUD', 'USD', 100000, 4, 14, 0.01, 100, 0.01, 500, 0.7221, 0.7224),
  ('USD/CAD', 'US Dollar vs Canadian Dollar', 'forex', 'USD', 'CAD', 100000, 4, 16, 0.01, 100, 0.01, 500, 1.3795, 1.3798),
  ('NZD/USD', 'New Zealand Dollar vs US Dollar', 'forex', 'NZD', 'USD', 100000, 4, 18, 0.01, 100, 0.01, 500, 0.5845, 0.5849),
  ('EUR/GBP', 'Euro vs British Pound', 'forex', 'EUR', 'GBP', 100000, 4, 15, 0.01, 100, 0.01, 500, 0.8585, 0.8588),
  ('EUR/JPY', 'Euro vs Japanese Yen', 'forex', 'EUR', 'JPY', 100000, 2, 18, 0.01, 100, 0.01, 500, 178.65, 178.69),
  ('GBP/JPY', 'British Pound vs Japanese Yen', 'forex', 'GBP', 'JPY', 100000, 2, 20, 0.01, 100, 0.01, 500, 208.10, 208.15),
  ('AUD/CAD', 'Australian Dollar vs Canadian Dollar', 'forex', 'AUD', 'CAD', 100000, 4, 16, 0.01, 100, 0.01, 500, 0.9960, 0.9964),
  ('AUD/CHF', 'Australian Dollar vs Swiss Franc', 'forex', 'AUD', 'CHF', 100000, 4, 16, 0.01, 100, 0.01, 500, 0.5845, 0.5849),
  ('AUD/JPY', 'Australian Dollar vs Japanese Yen', 'forex', 'AUD', 'JPY', 100000, 2, 16, 0.01, 100, 0.01, 500, 110.85, 110.89),
  ('AUD/NZD', 'Australian Dollar vs New Zealand Dollar', 'forex', 'AUD', 'NZD', 100000, 4, 18, 0.01, 100, 0.01, 500, 1.2350, 1.2354),
  ('CAD/CHF', 'Canadian Dollar vs Swiss Franc', 'forex', 'CAD', 'CHF', 100000, 4, 18, 0.01, 100, 0.01, 500, 0.5865, 0.5869),
  ('CAD/JPY', 'Canadian Dollar vs Japanese Yen', 'forex', 'CAD', 'JPY', 100000, 2, 18, 0.01, 100, 0.01, 500, 111.30, 111.34),
  ('CHF/JPY', 'Swiss Franc vs Japanese Yen', 'forex', 'CHF', 'JPY', 100000, 2, 18, 0.01, 100, 0.01, 500, 189.70, 189.74),
  ('EUR/AUD', 'Euro vs Australian Dollar', 'forex', 'EUR', 'AUD', 100000, 4, 16, 0.01, 100, 0.01, 500, 1.6110, 1.6114),
  ('EUR/CAD', 'Euro vs Canadian Dollar', 'forex', 'EUR', 'CAD', 100000, 4, 16, 0.01, 100, 0.01, 500, 1.6045, 1.6049),
  ('EUR/CHF', 'Euro vs Swiss Franc', 'forex', 'EUR', 'CHF', 100000, 4, 15, 0.01, 100, 0.01, 500, 0.9415, 0.9418),
  ('EUR/NZD', 'Euro vs New Zealand Dollar', 'forex', 'EUR', 'NZD', 100000, 4, 20, 0.01, 100, 0.01, 500, 1.9900, 1.9905),
  ('GBP/AUD', 'British Pound vs Australian Dollar', 'forex', 'GBP', 'AUD', 100000, 4, 20, 0.01, 100, 0.01, 500, 1.8760, 1.8765),
  ('GBP/CAD', 'British Pound vs Canadian Dollar', 'forex', 'GBP', 'CAD', 100000, 4, 20, 0.01, 100, 0.01, 500, 1.8685, 1.8690),
  ('GBP/CHF', 'British Pound vs Swiss Franc', 'forex', 'GBP', 'CHF', 100000, 4, 18, 0.01, 100, 0.01, 500, 1.0965, 1.0969),
  ('GBP/NZD', 'British Pound vs New Zealand Dollar', 'forex', 'GBP', 'NZD', 100000, 4, 22, 0.01, 100, 0.01, 500, 2.3180, 2.3186),
  ('NZD/CAD', 'New Zealand Dollar vs Canadian Dollar', 'forex', 'NZD', 'CAD', 100000, 4, 18, 0.01, 100, 0.01, 500, 0.8060, 0.8064),
  ('NZD/CHF', 'New Zealand Dollar vs Swiss Franc', 'forex', 'NZD', 'CHF', 100000, 4, 18, 0.01, 100, 0.01, 500, 0.4730, 0.4734),
  ('NZD/JPY', 'New Zealand Dollar vs Japanese Yen', 'forex', 'NZD', 'JPY', 100000, 2, 18, 0.01, 100, 0.01, 500, 89.75, 89.79),
  ('USD/SGD', 'US Dollar vs Singapore Dollar', 'forex', 'USD', 'SGD', 100000, 4, 20, 0.01, 100, 0.01, 500, 1.3280, 1.3284),
  ('USD/HKD', 'US Dollar vs Hong Kong Dollar', 'forex', 'USD', 'HKD', 100000, 4, 15, 0.01, 100, 0.01, 500, 7.7780, 7.7785),
  ('USD/TRY', 'US Dollar vs Turkish Lira', 'forex', 'USD', 'TRY', 100000, 2, 45, 0.01, 100, 0.01, 500, 48.51, 48.56),
  ('USD/ZAR', 'US Dollar vs South African Rand', 'forex', 'USD', 'ZAR', 100000, 2, 35, 0.01, 100, 0.01, 500, 18.25, 18.28),
  ('USD/MXN', 'US Dollar vs Mexican Peso', 'forex', 'USD', 'MXN', 100000, 2, 35, 0.01, 100, 0.01, 500, 20.35, 20.38),
  ('USD/SEK', 'US Dollar vs Swedish Krona', 'forex', 'USD', 'SEK', 100000, 2, 30, 0.01, 100, 0.01, 500, 10.45, 10.48),
  ('USD/NOK', 'US Dollar vs Norwegian Krone', 'forex', 'USD', 'NOK', 100000, 2, 30, 0.01, 100, 0.01, 500, 10.75, 10.78),
  ('USD/AED', 'US Dollar vs UAE Dirham', 'forex', 'USD', 'AED', 100000, 4, 10, 0.01, 100, 0.01, 500, 3.6725, 3.6730),
  ('USD/INR', 'US Dollar vs Indian Rupee', 'forex', 'USD', 'INR', 100000, 2, 25, 0.01, 100, 0.01, 500, 95.12, 95.17),
  ('USD/PKR', 'US Dollar vs Pakistani Rupee', 'forex', 'USD', 'PKR', 100000, 2, 50, 0.01, 100, 0.01, 500, 277.28, 277.58),
  ('WTI/USD', 'US Crude Oil Spot (WTI)', 'commodities', 'WTI', 'USD', 100, 2, 20, 0.01, 100, 0.01, 500, 102.00, 102.05),
  ('BRENT/USD', 'Brent Crude Oil Spot', 'commodities', 'BRENT', 'USD', 100, 2, 20, 0.01, 100, 0.01, 500, 106.38, 106.43),
  ('NGAS/USD', 'Natural Gas Spot', 'commodities', 'NGAS', 'USD', 100, 3, 25, 0.01, 100, 0.01, 500, 3.450, 3.458),
  ('BTC/USD', 'Bitcoin vs US Dollar', 'crypto', 'BTC', 'USD', 1, 2, 40, 0.01, 50, 0.01, 100, 96420.00, 96435.00),
  ('ETH/USD', 'Ethereum vs US Dollar', 'crypto', 'ETH', 'USD', 1, 2, 25, 0.01, 50, 0.01, 100, 2745.20, 2745.80),
  ('SOL/USD', 'Solana vs US Dollar', 'crypto', 'SOL', 'USD', 1, 2, 20, 0.01, 50, 0.01, 100, 185.20, 185.35),
  ('XRP/USD', 'Ripple vs US Dollar', 'crypto', 'XRP', 'USD', 1, 4, 10, 0.01, 50, 0.01, 100, 2.4510, 2.4525),
  ('BNB/USD', 'Binance Coin vs US Dollar', 'crypto', 'BNB', 'USD', 1, 2, 20, 0.01, 50, 0.01, 100, 645.00, 645.50),
  ('ADA/USD', 'Cardano vs US Dollar', 'crypto', 'ADA', 'USD', 1, 4, 10, 0.01, 50, 0.01, 100, 0.7850, 0.7860),
  ('DOGE/USD', 'Dogecoin vs US Dollar', 'crypto', 'DOGE', 'USD', 1, 4, 10, 0.01, 50, 0.01, 100, 0.2640, 0.2645),
  ('AVAX/USD', 'Avalanche vs US Dollar', 'crypto', 'AVAX', 'USD', 1, 2, 15, 0.01, 50, 0.01, 100, 34.80, 34.85),
  ('LINK/USD', 'Chainlink vs US Dollar', 'crypto', 'LINK', 'USD', 1, 2, 15, 0.01, 50, 0.01, 100, 18.50, 18.55),
  ('DOT/USD', 'Polkadot vs US Dollar', 'crypto', 'DOT', 'USD', 1, 2, 12, 0.01, 50, 0.01, 100, 6.25, 6.28),
  ('NEAR/USD', 'NEAR Protocol vs US Dollar', 'crypto', 'NEAR', 'USD', 1, 2, 12, 0.01, 50, 0.01, 100, 5.40, 5.43),
  ('LTC/USD', 'Litecoin vs US Dollar', 'crypto', 'LTC', 'USD', 1, 2, 18, 0.01, 50, 0.01, 100, 112.50, 112.70),
  ('US30/USD', 'Wall Street 30 (Dow Jones)', 'indices', 'US30', 'USD', 1, 1, 25, 0.01, 100, 0.01, 200, 44250.00, 44255.00),
  ('NAS100/USD', 'US Tech 100 (Nasdaq)', 'indices', 'NAS100', 'USD', 1, 1, 20, 0.01, 100, 0.01, 200, 21380.00, 21384.00),
  ('SPX500/USD', 'US 500 (S&P 500)', 'indices', 'SPX500', 'USD', 1, 1, 15, 0.01, 100, 0.01, 200, 6015.00, 6016.50),
  ('GER40/EUR', 'Germany 40 (DAX)', 'indices', 'GER40', 'EUR', 1, 1, 20, 0.01, 100, 0.01, 200, 20450.00, 20454.00),
  ('UK100/GBP', 'UK 100 (FTSE 100)', 'indices', 'UK100', 'GBP', 1, 1, 18, 0.01, 100, 0.01, 200, 8420.00, 8423.50),
  ('JP225/USD', 'Japan 225 (Nikkei)', 'indices', 'JP225', 'USD', 1, 1, 25, 0.01, 100, 0.01, 200, 38950.00, 38958.00),
  ('AAPL/USD', 'Apple Inc.', 'stocks', 'AAPL', 'USD', 10, 2, 15, 0.01, 100, 0.01, 100, 238.40, 238.55),
  ('NVDA/USD', 'NVIDIA Corporation', 'stocks', 'NVDA', 'USD', 10, 2, 15, 0.01, 100, 0.01, 100, 142.60, 142.75),
  ('TSLA/USD', 'Tesla Inc.', 'stocks', 'TSLA', 'USD', 10, 2, 20, 0.01, 100, 0.01, 100, 348.50, 348.75),
  ('AMZN/USD', 'Amazon.com Inc.', 'stocks', 'AMZN', 'USD', 10, 2, 15, 0.01, 100, 0.01, 100, 212.80, 212.95),
  ('MSFT/USD', 'Microsoft Corporation', 'stocks', 'MSFT', 'USD', 10, 2, 15, 0.01, 100, 0.01, 100, 428.20, 428.40),
  ('GOOGL/USD', 'Alphabet Inc. (Google)', 'stocks', 'GOOGL', 'USD', 10, 2, 15, 0.01, 100, 0.01, 100, 184.50, 184.65)
) AS v(symbol, name, category, base_currency, quote_currency, contract_size, digits,
       spread_markup_points, min_lots, max_lots, lot_step, max_leverage, seed_bid, seed_ask)
ON CONFLICT (symbol) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 3. AUTHORITATIVE PRICE CACHE
--    Written by the price publisher (service_role) and, when no fresh publisher
--    quote exists, by band-validated client submissions. `source` makes every
--    client-priced execution auditable.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_quotes (
    symbol        VARCHAR(20) PRIMARY KEY REFERENCES public.instruments(symbol) ON DELETE CASCADE,
    bid           NUMERIC(18, 8) NOT NULL CHECK (bid > 0),
    ask           NUMERIC(18, 8) NOT NULL CHECK (ask > 0),
    quote_to_usd  NUMERIC(20, 10) NOT NULL DEFAULT 1 CHECK (quote_to_usd > 0),
    source        VARCHAR(16)   NOT NULL DEFAULT 'client' CHECK (source IN ('publisher', 'client', 'seed')),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_market_quotes_updated ON public.market_quotes(updated_at DESC);

-- ------------------------------------------------------------------------------
-- 4. TRADES TABLE EXTENSIONS (audit + idempotency + fee model)
-- ------------------------------------------------------------------------------
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS commission        NUMERIC(18, 4) NOT NULL DEFAULT 0;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS swap              NUMERIC(18, 4) NOT NULL DEFAULT 0;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS quote_to_usd_rate NUMERIC(20, 10) NOT NULL DEFAULT 1;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS requested_price   NUMERIC(18, 5);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS spread_at_open    NUMERIC(18, 8);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS open_bid          NUMERIC(18, 8);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS open_ask          NUMERIC(18, 8);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS close_bid         NUMERIC(18, 8);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS close_ask         NUMERIC(18, 8);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS price_source      VARCHAR(16);
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS client_request_id TEXT;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS filled_at         TIMESTAMPTZ;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS cancelled_at      TIMESTAMPTZ;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS expires_at        TIMESTAMPTZ;
ALTER TABLE public.trades ADD COLUMN IF NOT EXISTS reject_reason     TEXT;

-- open_time must not be nullable for pending orders that have never filled.
ALTER TABLE public.trades ALTER COLUMN open_time SET DEFAULT NOW();

-- Widen the status domain: pending orders can now also be rejected or expired.
ALTER TABLE public.trades DROP CONSTRAINT IF EXISTS trades_status_check;
ALTER TABLE public.trades ADD CONSTRAINT trades_status_check
    CHECK (status IN ('pending', 'open', 'closed', 'cancelled', 'liquidated', 'rejected', 'expired'));

ALTER TABLE public.trades DROP CONSTRAINT IF EXISTS trades_type_check;
ALTER TABLE public.trades ADD CONSTRAINT trades_type_check
    CHECK (type IN ('market', 'limit', 'stop', 'stopLimit'));

-- Idempotency: one financial request id -> at most one trade row.
CREATE UNIQUE INDEX IF NOT EXISTS uq_trades_client_request
    ON public.trades(user_id, client_request_id)
    WHERE client_request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_trades_pending
    ON public.trades(symbol, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_trades_open_symbol
    ON public.trades(symbol, status) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_trades_user_open
    ON public.trades(user_id) WHERE status IN ('open', 'pending');

-- ------------------------------------------------------------------------------
-- 5. WALLETS: stop minting free money on row creation
-- ------------------------------------------------------------------------------
ALTER TABLE public.wallets ALTER COLUMN balance SET DEFAULT 0.0000;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS is_frozen BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.wallets DROP CONSTRAINT IF EXISTS wallets_held_margin_nonneg;
ALTER TABLE public.wallets ADD CONSTRAINT wallets_held_margin_nonneg CHECK (held_margin >= 0);

-- ------------------------------------------------------------------------------
-- 6. LEDGER: idempotency so a retry cannot double-post
-- ------------------------------------------------------------------------------
ALTER TABLE public.ledger_entries ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.ledger_entries ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'USD';

CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_idempotency
    ON public.ledger_entries(idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ledger_reference ON public.ledger_entries(reference_id);
CREATE INDEX IF NOT EXISTS idx_ledger_user_created ON public.ledger_entries(user_id, created_at DESC);

-- ------------------------------------------------------------------------------
-- 7. ADMIN BALANCE ADJUSTMENTS (audit trail)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_balance_adjustments (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        TEXT           NOT NULL,
    admin_id       TEXT           NOT NULL,
    amount         NUMERIC(18, 4) NOT NULL CHECK (amount <> 0),
    reason         TEXT           NOT NULL,
    balance_before NUMERIC(18, 4) NOT NULL,
    balance_after  NUMERIC(18, 4) NOT NULL,
    request_id     TEXT,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_admin_adjustment_request
    ON public.admin_balance_adjustments(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_admin_adj_user ON public.admin_balance_adjustments(user_id, created_at DESC);

-- ------------------------------------------------------------------------------
-- 8. WITHDRAWALS (request -> admin approval; funds held, never client-debited)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.withdrawals (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          TEXT           NOT NULL,
    amount           NUMERIC(18, 4) NOT NULL CHECK (amount > 0),
    currency         VARCHAR(10)    NOT NULL DEFAULT 'USD',
    method           VARCHAR(40),
    destination      TEXT,
    status           VARCHAR(20)    NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
    request_id       TEXT,
    reviewed_by      TEXT,
    reviewed_at      TIMESTAMPTZ,
    reject_reason    TEXT,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_withdrawal_request
    ON public.withdrawals(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_withdrawals_user ON public.withdrawals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.withdrawals(status);

-- ==============================================================================
-- 9. ROW LEVEL SECURITY — READ-ONLY FOR CLIENTS
--
-- Every financial write now goes through a SECURITY DEFINER RPC. The RPC owner
-- bypasses RLS, so removing the client write policies below does not break any
-- legitimate flow — it only removes the ability to POST/PATCH money directly.
-- ==============================================================================
ALTER TABLE public.wallets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trades          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instruments     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_quotes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.broker_config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawals     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_balance_adjustments ENABLE ROW LEVEL SECURITY;

-- Drop the permissive FOR ALL policies created by supabase_schema.sql.
DROP POLICY IF EXISTS "Users can view own wallet"  ON public.wallets;
DROP POLICY IF EXISTS "Users can view own trades"  ON public.trades;
DROP POLICY IF EXISTS "Users can view own ledger"  ON public.ledger_entries;

-- Wallets: read own row only. No INSERT/UPDATE/DELETE policy exists, so those
-- verbs are denied for `anon` and `authenticated`.
DROP POLICY IF EXISTS "wallets_select_own" ON public.wallets;
CREATE POLICY "wallets_select_own" ON public.wallets
    FOR SELECT TO authenticated
    USING (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "wallets_select_admin" ON public.wallets;
CREATE POLICY "wallets_select_admin" ON public.wallets
    FOR SELECT TO authenticated
    USING (public.fx_is_admin());

-- Trades: read own rows only.
DROP POLICY IF EXISTS "trades_select_own" ON public.trades;
CREATE POLICY "trades_select_own" ON public.trades
    FOR SELECT TO authenticated
    USING (auth.uid()::text = user_id OR public.fx_is_admin());

-- Ledger: read own rows only. Append-only through RPCs.
DROP POLICY IF EXISTS "ledger_select_own" ON public.ledger_entries;
CREATE POLICY "ledger_select_own" ON public.ledger_entries
    FOR SELECT TO authenticated
    USING (auth.uid()::text = user_id OR public.fx_is_admin());

-- Instruments / quotes / config: public reference data, read-only.
DROP POLICY IF EXISTS "instruments_select_all" ON public.instruments;
CREATE POLICY "instruments_select_all" ON public.instruments
    FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "market_quotes_select_all" ON public.market_quotes;
CREATE POLICY "market_quotes_select_all" ON public.market_quotes
    FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "broker_config_select_all" ON public.broker_config;
CREATE POLICY "broker_config_select_all" ON public.broker_config
    FOR SELECT TO authenticated USING (TRUE);

-- Withdrawals: user reads own requests, admin reads all. Writes via RPC only.
DROP POLICY IF EXISTS "withdrawals_select_own" ON public.withdrawals;
CREATE POLICY "withdrawals_select_own" ON public.withdrawals
    FOR SELECT TO authenticated
    USING (auth.uid()::text = user_id OR public.fx_is_admin());

-- Admin adjustments: only admins may read the audit trail.
DROP POLICY IF EXISTS "admin_adj_select_admin" ON public.admin_balance_adjustments;
CREATE POLICY "admin_adj_select_admin" ON public.admin_balance_adjustments
    FOR SELECT TO authenticated
    USING (public.fx_is_admin() OR auth.uid()::text = user_id);

-- Belt and braces: revoke table-level write grants from the client roles so a
-- future permissive policy cannot silently re-open a write path.
REVOKE INSERT, UPDATE, DELETE ON public.wallets        FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.trades         FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ledger_entries FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.instruments    FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.market_quotes  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.broker_config  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.withdrawals    FROM anon, authenticated;
REVOKE ALL ON public.admin_balance_adjustments         FROM anon;

-- ------------------------------------------------------------------------------
-- 10. REALTIME: push authoritative changes back to Flutter
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.trades;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.ledger_entries;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
