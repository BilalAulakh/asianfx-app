-- ##############################################################################
--  HOTFIX_uuid.sql  —  run this on its own, it is tiny and cannot fail half way
--
--  Symptom: "function uuid_generate_v4() does not exist" when placing an order.
--
--  Cause: on Supabase the uuid-ossp extension is installed into the `extensions`
--  schema. Every SECURITY DEFINER function here pins `SET search_path = public`,
--  so anything still calling uuid_generate_v4() by name — an older deployed copy
--  of an RPC, or a column DEFAULT inherited from supabase_schema.sql — cannot
--  resolve it at run time, even though it resolved fine at CREATE TABLE time.
--
--  This does three independent things, any one of which fixes it:
--    1. repoints every public column DEFAULT onto core gen_random_uuid()
--    2. leaves a public.uuid_generate_v4() shim so the bare name always resolves
--    3. records a version marker so the deployed state can be checked remotely
-- ##############################################################################

-- 1. Repoint every public column default that still names uuid_generate_v4().
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
        RAISE NOTICE 'repointed default: public.%.%', r.table_name, r.column_name;
    END LOOP;
END $$;

-- 2. Compatibility shim: make the bare name resolvable under search_path=public.
--    gen_random_uuid() also returns a v4 UUID, so the semantics are identical.
--    Harmless if uuid-ossp is present elsewhere — this copy simply wins on the
--    `public` search path used by the trading functions.
CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
VOLATILE
PARALLEL SAFE
AS $$ SELECT gen_random_uuid() $$;

GRANT EXECUTE ON FUNCTION public.uuid_generate_v4() TO authenticated, anon, service_role;

-- 3. Deployed-version marker, so the running schema can be identified remotely.
CREATE OR REPLACE FUNCTION public.fx_engine_version()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    -- Self-contained on purpose: no dependency on tables/functions that may not
    -- be deployed yet, so this hotfix can never fail on a partial schema.
    SELECT jsonb_build_object(
        'engine', '2026-10-01.5',
        'uuid_source', 'gen_random_uuid',
        'uuid_shim', to_regprocedure('public.uuid_generate_v4()') IS NOT NULL,
        'open_trade_uses_ossp', EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'rpc_open_trade'
              AND pg_get_functiondef(p.oid) ILIKE '%uuid_generate_v4%'
        )
    );
$$;

GRANT EXECUTE ON FUNCTION public.fx_engine_version() TO authenticated, anon, service_role;
