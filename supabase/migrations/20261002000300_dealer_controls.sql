-- ==============================================================================
-- MIGRATION: 20261002000300_dealer_controls.sql
--
-- Dealer controls that used to live only in the admin's phone memory
-- (MarketFeedService._spreadMarkupMap / AdminCubit.spreadMultiplier) are now
-- persisted, audited, and actually applied by the price publisher.
--
--   instruments.spread_markup_points  <- rpc_admin_set_markup (0..500, audited)
--   broker_config.spread_multiplier   <- rpc_admin_set_spread_multiplier (1..10)
--
-- fx-price-sweep publishes bid/ask with
--   spread = round(spread_markup_points * spread_multiplier) * point_size
-- ==============================================================================

ALTER TABLE public.broker_config
    ADD COLUMN IF NOT EXISTS spread_multiplier NUMERIC(6, 3) NOT NULL DEFAULT 1.000;

ALTER TABLE public.broker_config DROP CONSTRAINT IF EXISTS broker_config_spread_multiplier_check;
ALTER TABLE public.broker_config ADD CONSTRAINT broker_config_spread_multiplier_check
    CHECK (spread_multiplier >= 1 AND spread_multiplier <= 10);

ALTER TABLE public.instruments DROP CONSTRAINT IF EXISTS instruments_spread_markup_points_check;
ALTER TABLE public.instruments ADD CONSTRAINT instruments_spread_markup_points_check
    CHECK (spread_markup_points >= 0 AND spread_markup_points <= 500);

-- ------------------------------------------------------------------------------
-- Append-only audit trail for dealer / broker configuration changes.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_config_audit (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id    TEXT        NOT NULL,
    action      TEXT        NOT NULL,
    target      TEXT,
    old_value   JSONB,
    new_value   JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_config_audit_created ON public.admin_config_audit (created_at DESC);

ALTER TABLE public.admin_config_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_config_audit_select_admin" ON public.admin_config_audit;
CREATE POLICY "admin_config_audit_select_admin" ON public.admin_config_audit
    FOR SELECT TO authenticated
    USING (public.fx_is_admin());

REVOKE ALL ON public.admin_config_audit FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.admin_config_audit FROM authenticated;

-- ------------------------------------------------------------------------------
-- Per-instrument dealer markup
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_set_markup(p_symbol TEXT, p_points INTEGER)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_old   INTEGER;
    v_new   INTEGER;
BEGIN
    v_admin := public.fx_require_admin();

    IF p_points IS NULL THEN
        RAISE EXCEPTION 'BAD_MARKUP: markup points are required' USING ERRCODE = '22023';
    END IF;
    v_new := LEAST(GREATEST(p_points, 0), 500);

    SELECT spread_markup_points INTO v_old
    FROM public.instruments WHERE symbol = p_symbol FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UNKNOWN_INSTRUMENT: % is not offered by this broker', p_symbol
            USING ERRCODE = '22023';
    END IF;

    IF v_old IS DISTINCT FROM v_new THEN
        UPDATE public.instruments
           SET spread_markup_points = v_new, updated_at = NOW()
         WHERE symbol = p_symbol;

        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_markup', p_symbol,
                jsonb_build_object('spread_markup_points', v_old),
                jsonb_build_object('spread_markup_points', v_new, 'requested', p_points));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'symbol', p_symbol,
                              'spread_markup_points', v_new, 'previous', v_old);
END;
$$;

-- ------------------------------------------------------------------------------
-- Global spread multiplier (news / volatility widening)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_admin_set_spread_multiplier(p_multiplier NUMERIC)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_old   NUMERIC;
    v_new   NUMERIC;
BEGIN
    v_admin := public.fx_require_admin();

    IF p_multiplier IS NULL THEN
        RAISE EXCEPTION 'BAD_MULTIPLIER: a multiplier is required' USING ERRCODE = '22023';
    END IF;
    v_new := ROUND(LEAST(GREATEST(p_multiplier, 1), 10), 3);

    SELECT spread_multiplier INTO v_old FROM public.broker_config WHERE id = 1 FOR UPDATE;

    IF v_old IS DISTINCT FROM v_new THEN
        UPDATE public.broker_config SET spread_multiplier = v_new, updated_at = NOW() WHERE id = 1;

        INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
        VALUES (v_admin, 'set_spread_multiplier', 'broker_config',
                jsonb_build_object('spread_multiplier', v_old),
                jsonb_build_object('spread_multiplier', v_new, 'requested', p_multiplier));
    END IF;

    RETURN jsonb_build_object('status', 'success', 'spread_multiplier', v_new, 'previous', v_old);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_admin_set_markup(TEXT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_admin_set_spread_multiplier(NUMERIC) FROM PUBLIC, anon;
-- Admin-gated inside the functions (fx_require_admin).
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_markup(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_admin_set_spread_multiplier(NUMERIC) TO authenticated;
