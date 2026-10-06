-- ==============================================================================
-- MIGRATION: 20261006000300_realtime_market_quotes.sql
--
-- Push published prices to the app the moment fx-price-sweep writes them.
--
-- market_quotes joins the supabase_realtime publication, so every
-- rpc_publish_quotes upsert is delivered to subscribed apps over the existing
-- websocket instead of each app polling the table every few seconds. RLS
-- (market_quotes_select_all: authenticated may read) still decides who
-- receives the rows. The app keeps a slow poll as a fallback.
--
-- Idempotent; safe to re-run.
-- ==============================================================================

DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.market_quotes;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
END $$;
