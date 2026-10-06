-- ##############################################################################
--  APPLY_PENDING.sql  —  GENERATED, DO NOT EDIT
--
--  Paste into the Supabase SQL Editor and Run. Safe to repeat.
--
--    1. 20261001000000_trading_core_schema.sql
--    2. 20261001000100_trading_rpcs.sql
--    3. 20261001000200_trading_public_rpcs.sql
--    4. 20261001000300_kyc_manual_review.sql
-- ##############################################################################



-- ==== BEGIN 20261001000000_trading_core_schema.sql ========================================

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


-- ==== END 20261001000000_trading_core_schema.sql ==========================================


-- ==== BEGIN 20261001000100_trading_rpcs.sql ========================================

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


-- ==== END 20261001000100_trading_rpcs.sql ==========================================


-- ==== BEGIN 20261001000200_trading_public_rpcs.sql ========================================

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


-- ==== END 20261001000200_trading_public_rpcs.sql ==========================================


-- ==== BEGIN 20261001000300_kyc_manual_review.sql ========================================

-- ==============================================================================
-- MIGRATION: 20261001000300_kyc_manual_review.sql
--
-- Manual KYC with administrator approval, enforced by the database.
--
-- Three problems this closes:
--
--  1. public.kyc_profiles did not exist on this project at all, so every KYC
--     save silently failed and fell back to on-device SharedPreferences —
--     the compliance record lived only on the applicant's phone.
--
--  2. The app decided who is an administrator purely client-side
--     (email == 'admin@asianfx.com'). The database had no idea, so every
--     admin-gated RPC would answer FORBIDDEN. Admins are now rows in
--     public.broker_admins.
--
--  3. The original KYC policy allowed a user to UPDATE their own profile row,
--     status column included — a self-service "APPROVED". Privileged columns
--     are now owned by the database and can only move through rpc_review_kyc.
-- ==============================================================================

-- NOTE: gen_random_uuid() (PostgreSQL core, pg_catalog) is used throughout
-- instead of uuid_generate_v4(). On Supabase the uuid-ossp extension lives in
-- the `extensions` schema, which is NOT on the `SET search_path = public` these
-- SECURITY DEFINER functions pin — so uuid_generate_v4() resolved at CREATE
-- TABLE time but failed at run time with "function uuid_generate_v4() does not
-- exist" the moment an RPC tried to call it.

-- ------------------------------------------------------------------------------
-- A. WHO IS AN ADMINISTRATOR
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.broker_admins (
    user_id    TEXT PRIMARY KEY,
    email      TEXT,
    note       TEXT,
    added_by   TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.broker_admins ENABLE ROW LEVEL SECURITY;
-- No client policy at all: readable only through the SECURITY DEFINER helper
-- below, writable only by the service role or a database session.
REVOKE ALL ON public.broker_admins FROM anon, authenticated;

-- Seed from the account the app already treats as the administrator.
INSERT INTO public.broker_admins (user_id, email, note, added_by)
SELECT u.id::TEXT, u.email, 'Seeded from the app''s built-in admin address', 'migration'
FROM auth.users u
WHERE LOWER(u.email) = 'admin@asianfx.com'
ON CONFLICT (user_id) DO NOTHING;

-- Extend the admin check to consult that table.
-- SECURITY DEFINER so it can read broker_admins past its own RLS.
CREATE OR REPLACE FUNCTION public.fx_is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
        OR COALESCE(auth.jwt() ->> 'role', '') IN ('admin', 'superadmin')
        OR COALESCE(auth.jwt() -> 'app_metadata'  ->> 'role', '') IN ('admin', 'superadmin')
        OR COALESCE(auth.jwt() -> 'user_metadata' ->> 'role', '') IN ('admin', 'superadmin')
        OR EXISTS (
            SELECT 1 FROM public.broker_admins b
            WHERE b.user_id = auth.uid()::TEXT
        );
$$;

-- ------------------------------------------------------------------------------
-- B. KYC TABLES
--    Column-for-column compatible with KycProfileEntity / KycDocumentEntity /
--    KycAuditLogEntry so the existing Dart mapping keeps working.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kyc_profiles (
    id                   TEXT PRIMARY KEY,
    user_id              TEXT NOT NULL UNIQUE,
    first_name           TEXT NOT NULL,
    middle_name          TEXT,
    last_name            TEXT NOT NULL,
    date_of_birth        TIMESTAMPTZ,
    nationality          TEXT NOT NULL DEFAULT 'Pakistan',
    country_of_residence TEXT NOT NULL DEFAULT 'Pakistan',
    address              TEXT NOT NULL,
    city                 TEXT NOT NULL,
    state                TEXT NOT NULL,
    postal_code          TEXT NOT NULL,
    status               VARCHAR(32) NOT NULL DEFAULT 'NOT_STARTED',
    rejection_reason     TEXT,
    resubmission_notes   TEXT,
    document_number      TEXT,
    identity_doc_type    VARCHAR(32) DEFAULT 'CNIC',
    address_doc_type     VARCHAR(32) DEFAULT 'UTILITY_BILL',
    submitted_at         TIMESTAMPTZ,
    reviewed_at          TIMESTAMPTZ,
    reviewed_by          TEXT,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kyc_profiles_user_id ON public.kyc_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_profiles_status  ON public.kyc_profiles(status);

ALTER TABLE public.kyc_profiles DROP CONSTRAINT IF EXISTS kyc_profiles_status_check;
ALTER TABLE public.kyc_profiles ADD CONSTRAINT kyc_profiles_status_check
    CHECK (status IN ('NOT_STARTED', 'IN_PROGRESS', 'PENDING_REVIEW', 'MANUAL_REVIEW',
                      'APPROVED', 'REJECTED', 'RESUBMISSION_REQUIRED'));

CREATE TABLE IF NOT EXISTS public.kyc_documents (
    id                 TEXT PRIMARY KEY,
    kyc_id             TEXT NOT NULL REFERENCES public.kyc_profiles(id) ON DELETE CASCADE,
    user_id            TEXT NOT NULL,
    document_category  VARCHAR(32) NOT NULL,
    document_type      VARCHAR(32) NOT NULL,
    storage_path       TEXT,
    original_file_name TEXT NOT NULL,
    mime_type          VARCHAR(64) NOT NULL DEFAULT 'image/jpeg',
    file_size          BIGINT NOT NULL DEFAULT 0,
    document_side      VARCHAR(16) DEFAULT 'SINGLE',
    status             VARCHAR(32) NOT NULL DEFAULT 'PENDING_REVIEW',
    rejection_reason   TEXT,
    uploaded_at        TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_kyc_documents_kyc_id  ON public.kyc_documents(kyc_id);
CREATE INDEX IF NOT EXISTS idx_kyc_documents_user_id ON public.kyc_documents(user_id);

CREATE TABLE IF NOT EXISTS public.kyc_audit_logs (
    id           TEXT PRIMARY KEY,
    kyc_id       TEXT NOT NULL,
    user_id      TEXT NOT NULL,
    action       VARCHAR(64) NOT NULL,
    performed_by TEXT NOT NULL DEFAULT 'SYSTEM',
    timestamp    TIMESTAMPTZ DEFAULT NOW(),
    notes        TEXT
);

CREATE INDEX IF NOT EXISTS idx_kyc_audit_logs_kyc_id  ON public.kyc_audit_logs(kyc_id);
CREATE INDEX IF NOT EXISTS idx_kyc_audit_logs_user_id ON public.kyc_audit_logs(user_id);

-- ------------------------------------------------------------------------------
-- C. THE VERDICT BELONGS TO THE DATABASE
--
-- The applicant may still upsert their own profile and documents — that keeps
-- the existing Flutter datasource working unchanged. This trigger simply
-- ignores any attempt to write the columns that represent the verdict.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_kyc_guard_verdict()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- rpc_submit_kyc / rpc_review_kyc set this transaction-local flag; they are
    -- the only sanctioned way to move the verdict columns.
    IF COALESCE(current_setting('fx.kyc_privileged', TRUE), '') = 'on' THEN
        RETURN NEW;
    END IF;

    IF public.fx_is_admin() OR public.fx_is_backend() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- A brand new application always starts from zero, whatever was posted.
        NEW.status             := 'NOT_STARTED';
        NEW.submitted_at       := NULL;
        NEW.reviewed_at        := NULL;
        NEW.reviewed_by        := NULL;
        NEW.rejection_reason   := NULL;
        NEW.resubmission_notes := NULL;
        RETURN NEW;
    END IF;

    -- An approved record is frozen: identity data cannot be swapped afterwards.
    IF OLD.status = 'APPROVED' THEN
        RETURN OLD;
    END IF;

    -- Profile data may change; the verdict may not.
    NEW.status             := OLD.status;
    NEW.submitted_at       := OLD.submitted_at;
    NEW.reviewed_at        := OLD.reviewed_at;
    NEW.reviewed_by        := OLD.reviewed_by;
    NEW.rejection_reason   := OLD.rejection_reason;
    NEW.resubmission_notes := OLD.resubmission_notes;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kyc_guard_verdict ON public.kyc_profiles;
CREATE TRIGGER trg_kyc_guard_verdict
    BEFORE INSERT OR UPDATE ON public.kyc_profiles
    FOR EACH ROW EXECUTE FUNCTION public.fx_kyc_guard_verdict();

-- Document review state is the reviewer's too.
CREATE OR REPLACE FUNCTION public.fx_kyc_guard_document_verdict()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(current_setting('fx.kyc_privileged', TRUE), '') = 'on'
       OR public.fx_is_admin() OR public.fx_is_backend() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.status           := 'PENDING_REVIEW';
        NEW.rejection_reason := NULL;
        NEW.reviewed_at      := NULL;
        RETURN NEW;
    END IF;

    NEW.status           := OLD.status;
    NEW.rejection_reason := OLD.rejection_reason;
    NEW.reviewed_at      := OLD.reviewed_at;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kyc_guard_document_verdict ON public.kyc_documents;
CREATE TRIGGER trg_kyc_guard_document_verdict
    BEFORE INSERT OR UPDATE ON public.kyc_documents
    FOR EACH ROW EXECUTE FUNCTION public.fx_kyc_guard_document_verdict();

-- ------------------------------------------------------------------------------
-- D. ROW LEVEL SECURITY
-- ------------------------------------------------------------------------------
ALTER TABLE public.kyc_profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_documents  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own kyc profile"        ON public.kyc_profiles;
DROP POLICY IF EXISTS "Users can insert own kyc profile"      ON public.kyc_profiles;
DROP POLICY IF EXISTS "Users and admins can update kyc profile" ON public.kyc_profiles;

CREATE POLICY "kyc_profiles_select" ON public.kyc_profiles
    FOR SELECT TO authenticated
    USING (auth.uid()::TEXT = user_id OR public.fx_is_admin());

CREATE POLICY "kyc_profiles_insert_own" ON public.kyc_profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid()::TEXT = user_id);

CREATE POLICY "kyc_profiles_update_own" ON public.kyc_profiles
    FOR UPDATE TO authenticated
    USING (auth.uid()::TEXT = user_id OR public.fx_is_admin())
    WITH CHECK (auth.uid()::TEXT = user_id OR public.fx_is_admin());

DROP POLICY IF EXISTS "Users can view own kyc documents"   ON public.kyc_documents;
DROP POLICY IF EXISTS "Users can insert own kyc documents" ON public.kyc_documents;
DROP POLICY IF EXISTS "Admins can update kyc documents"    ON public.kyc_documents;

CREATE POLICY "kyc_documents_select" ON public.kyc_documents
    FOR SELECT TO authenticated
    USING (auth.uid()::TEXT = user_id OR public.fx_is_admin());

CREATE POLICY "kyc_documents_insert_own" ON public.kyc_documents
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid()::TEXT = user_id);

CREATE POLICY "kyc_documents_update" ON public.kyc_documents
    FOR UPDATE TO authenticated
    USING (auth.uid()::TEXT = user_id OR public.fx_is_admin())
    WITH CHECK (auth.uid()::TEXT = user_id OR public.fx_is_admin());

DROP POLICY IF EXISTS "Users and system can view audit logs"   ON public.kyc_audit_logs;
DROP POLICY IF EXISTS "Users and system can insert audit logs" ON public.kyc_audit_logs;

-- Audit logs are written by the review RPCs only; clients may read their own.
CREATE POLICY "kyc_audit_select" ON public.kyc_audit_logs
    FOR SELECT TO authenticated
    USING (auth.uid()::TEXT = user_id OR public.fx_is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.kyc_audit_logs FROM anon, authenticated;
REVOKE DELETE ON public.kyc_profiles, public.kyc_documents FROM anon, authenticated;

-- ------------------------------------------------------------------------------
-- E. SUBMIT FOR MANUAL REVIEW  (applicant)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_submit_kyc()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid  TEXT;
    v_p    public.kyc_profiles;
    v_docs INTEGER;
BEGIN
    v_uid := public.fx_require_user_id();

    SELECT * INTO v_p FROM public.kyc_profiles WHERE user_id = v_uid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'KYC_PROFILE_MISSING: complete your verification details before submitting'
            USING ERRCODE = '22023';
    END IF;

    IF v_p.status = 'APPROVED' THEN
        RETURN jsonb_build_object('status', 'already_approved', 'kyc_status', v_p.status);
    END IF;
    IF v_p.status IN ('PENDING_REVIEW', 'MANUAL_REVIEW') THEN
        RETURN jsonb_build_object('status', 'already_pending', 'kyc_status', v_p.status);
    END IF;

    SELECT COUNT(*) INTO v_docs FROM public.kyc_documents WHERE kyc_id = v_p.id;
    IF v_docs = 0 THEN
        RAISE EXCEPTION 'KYC_DOCUMENTS_MISSING: upload at least one document before submitting'
            USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('fx.kyc_privileged', 'on', TRUE);

    UPDATE public.kyc_profiles
       SET status             = 'PENDING_REVIEW',
           submitted_at       = NOW(),
           rejection_reason   = NULL,
           resubmission_notes = NULL,
           reviewed_at        = NULL,
           reviewed_by        = NULL,
           updated_at         = NOW()
     WHERE id = v_p.id;

    INSERT INTO public.kyc_audit_logs (id, kyc_id, user_id, action, performed_by, notes)
    VALUES (gen_random_uuid()::TEXT, v_p.id, v_uid,
            CASE WHEN v_p.status IN ('REJECTED', 'RESUBMISSION_REQUIRED') THEN 'RESUBMITTED' ELSE 'SUBMITTED' END,
            v_uid,
            format('Submitted for manual compliance review with %s document(s).', v_docs));

    RETURN jsonb_build_object(
        'status', 'success',
        'kyc_id', v_p.id,
        'kyc_status', 'PENDING_REVIEW',
        'documents', v_docs,
        'submitted_at', NOW());
END;
$$;

-- ------------------------------------------------------------------------------
-- F. REVIEW  (administrator only)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_review_kyc(
    p_kyc_id   TEXT,
    p_decision TEXT,
    p_notes    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin    TEXT;
    v_p        public.kyc_profiles;
    v_decision TEXT;
    v_status   TEXT;
    v_action   TEXT;
BEGIN
    v_admin := public.fx_require_admin();

    v_decision := UPPER(COALESCE(p_decision, ''));
    IF v_decision NOT IN ('APPROVE', 'REJECT', 'RESUBMIT') THEN
        RAISE EXCEPTION 'BAD_DECISION: decision must be APPROVE, REJECT or RESUBMIT'
            USING ERRCODE = '22023';
    END IF;

    IF v_decision IN ('REJECT', 'RESUBMIT') AND COALESCE(TRIM(p_notes), '') = '' THEN
        RAISE EXCEPTION 'REASON_REQUIRED: a written reason is required to % an application',
            LOWER(v_decision) USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_p FROM public.kyc_profiles WHERE id = p_kyc_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'KYC_NOT_FOUND: no application %', p_kyc_id USING ERRCODE = '22023';
    END IF;

    v_status := CASE v_decision
                    WHEN 'APPROVE'  THEN 'APPROVED'
                    WHEN 'REJECT'   THEN 'REJECTED'
                    ELSE 'RESUBMISSION_REQUIRED'
                END;
    v_action := CASE v_decision
                    WHEN 'APPROVE'  THEN 'APPROVED'
                    WHEN 'REJECT'   THEN 'REJECTED'
                    ELSE 'RESUBMISSION_REQUESTED'
                END;

    IF v_p.status = v_status THEN
        RETURN jsonb_build_object('status', 'already_reviewed', 'kyc_status', v_p.status);
    END IF;

    PERFORM set_config('fx.kyc_privileged', 'on', TRUE);

    UPDATE public.kyc_profiles
       SET status             = v_status,
           reviewed_at        = NOW(),
           reviewed_by        = v_admin,
           rejection_reason   = CASE WHEN v_decision = 'REJECT'   THEN TRIM(p_notes) ELSE NULL END,
           resubmission_notes = CASE WHEN v_decision = 'RESUBMIT' THEN TRIM(p_notes) ELSE NULL END,
           updated_at         = NOW()
     WHERE id = p_kyc_id;

    INSERT INTO public.kyc_audit_logs (id, kyc_id, user_id, action, performed_by, notes)
    VALUES (gen_random_uuid()::TEXT, p_kyc_id, v_p.user_id, v_action, v_admin,
            COALESCE(NULLIF(TRIM(p_notes), ''),
                     format('Application %s by %s.', LOWER(v_status), v_admin)));

    RETURN jsonb_build_object(
        'status', 'success',
        'kyc_id', p_kyc_id,
        'user_id', v_p.user_id,
        'kyc_status', v_status,
        'reviewed_by', v_admin,
        'reviewed_at', NOW());
END;
$$;

-- ------------------------------------------------------------------------------
-- G. PRIVATE DOCUMENT STORAGE
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('kyc-documents', 'kyc-documents', FALSE)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Users can upload their own KYC docs" ON storage.objects;
CREATE POLICY "Users can upload their own KYC docs" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'kyc-documents'
        AND (storage.foldername(name))[1] = auth.uid()::TEXT
    );

DROP POLICY IF EXISTS "Users and admins can view KYC docs" ON storage.objects;
CREATE POLICY "Users and admins can view KYC docs" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'kyc-documents'
        AND ((storage.foldername(name))[1] = auth.uid()::TEXT OR public.fx_is_admin())
    );

-- ------------------------------------------------------------------------------
-- H. GRANTS & REALTIME
-- ------------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.rpc_submit_kyc() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_review_kyc(TEXT, TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.fx_kyc_guard_verdict() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fx_kyc_guard_document_verdict() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
    BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.kyc_profiles;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ------------------------------------------------------------------------------
-- I. DEPLOYED-VERSION MARKER
--    Lets the running schema be identified without database access, so "did the
--    migration actually apply?" is answerable instead of guessable.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fx_engine_version()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'engine', '2026-10-01.5',
        'uuid_source', 'gen_random_uuid',
        'kyc_module', public.fx_kyc_module_installed(),
        'instruments', (SELECT COUNT(*) FROM public.instruments),
        'admins', (SELECT COUNT(*) FROM public.broker_admins),
        'open_trade_uses_ossp', EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'rpc_open_trade'
              AND pg_get_functiondef(p.oid) ILIKE '%uuid_generate_v4%'
        )
    );
$$;

GRANT EXECUTE ON FUNCTION public.fx_engine_version() TO authenticated, anon, service_role;


-- ==== END 20261001000300_kyc_manual_review.sql ==========================================
