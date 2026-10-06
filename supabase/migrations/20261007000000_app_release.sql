-- ==============================================================================
-- MIGRATION: 20261007000000_app_release.sql
--
-- In-app updates for the Android app distributed from the website (no Play Store).
--
--   app_release (single row): the latest published build.
--     version_code      Android versionCode of the build (pubspec "+N").
--     version_name      what users see, e.g. "1.0.1".
--     apk_url           https download link (the website's /FXAsian.apk).
--     apk_sha256        optional: the app refuses a download that does not match.
--     min_version_code  builds below this must update before they can be used.
--     notes             "What's new" shown in the update dialog.
--
--   rpc_get_app_release()            anyone (also before sign-in) may read it.
--   rpc_admin_publish_app_release()  admin only; audited in admin_config_audit.
--
-- Android itself refuses an update that is not signed with the app's key, so a
-- wrong link can never replace the app with someone else's build. Idempotent.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.app_release (
    id               SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    version_code     INTEGER NOT NULL DEFAULT 1 CHECK (version_code >= 1),
    version_name     TEXT    NOT NULL DEFAULT '1.0.0',
    apk_url          TEXT,
    apk_sha256       TEXT CHECK (apk_sha256 IS NULL OR apk_sha256 ~ '^[0-9a-f]{64}$'),
    min_version_code INTEGER NOT NULL DEFAULT 1 CHECK (min_version_code >= 1),
    notes            TEXT,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (min_version_code <= version_code)
);

INSERT INTO public.app_release (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- No direct table access: reads and writes go through the RPCs below.
ALTER TABLE public.app_release ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_release FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_get_app_release()
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'version_code', version_code,
        'version_name', version_name,
        'apk_url', apk_url,
        'apk_sha256', apk_sha256,
        'min_version_code', min_version_code,
        'notes', notes,
        'updated_at', updated_at)
    FROM public.app_release WHERE id = 1;
$$;

CREATE OR REPLACE FUNCTION public.rpc_admin_publish_app_release(
    p_version_code     INTEGER,
    p_version_name     TEXT,
    p_apk_url          TEXT,
    p_notes            TEXT    DEFAULT NULL,
    p_force            BOOLEAN DEFAULT FALSE,
    p_apk_sha256       TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin TEXT;
    v_old   public.app_release;
    v_new   public.app_release;
    v_name  TEXT := btrim(COALESCE(p_version_name, ''));
    v_url   TEXT := btrim(COALESCE(p_apk_url, ''));
    v_sha   TEXT := NULLIF(lower(btrim(COALESCE(p_apk_sha256, ''))), '');
BEGIN
    v_admin := public.fx_require_admin();

    SELECT * INTO v_old FROM public.app_release WHERE id = 1 FOR UPDATE;

    IF p_version_code IS NULL OR p_version_code < 1 OR p_version_code > 2100000000 THEN
        RAISE EXCEPTION 'BAD_VERSION: build number must be a positive whole number' USING ERRCODE = '22023';
    END IF;
    IF p_version_code < v_old.version_code THEN
        RAISE EXCEPTION 'OLDER_VERSION: build % is older than the published build %', p_version_code, v_old.version_code
            USING ERRCODE = '22023';
    END IF;
    IF v_name !~ '^[0-9A-Za-z.+_-]{1,32}$' THEN
        RAISE EXCEPTION 'BAD_VERSION_NAME: use a version like 1.0.1' USING ERRCODE = '22023';
    END IF;
    IF v_url !~ '^https://[^\s]+$' OR length(v_url) > 1000 THEN
        RAISE EXCEPTION 'BAD_URL: the download link must start with https://' USING ERRCODE = '22023';
    END IF;
    IF v_sha IS NOT NULL AND v_sha !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'BAD_SHA256: the SHA-256 must be 64 hex characters' USING ERRCODE = '22023';
    END IF;

    UPDATE public.app_release SET
        version_code     = p_version_code,
        version_name     = v_name,
        apk_url          = v_url,
        apk_sha256       = v_sha,
        notes            = NULLIF(left(btrim(COALESCE(p_notes, '')), 2000), ''),
        min_version_code = CASE WHEN COALESCE(p_force, FALSE) THEN p_version_code
                                ELSE LEAST(min_version_code, p_version_code) END,
        updated_at       = NOW()
    WHERE id = 1
    RETURNING * INTO v_new;

    INSERT INTO public.admin_config_audit (admin_id, action, target, old_value, new_value)
    VALUES (v_admin, 'publish_app_release', 'app_release', to_jsonb(v_old), to_jsonb(v_new));

    RETURN jsonb_build_object('status', 'success', 'release', public.rpc_get_app_release());
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_app_release() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_get_app_release() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_admin_publish_app_release(INTEGER, TEXT, TEXT, TEXT, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_admin_publish_app_release(INTEGER, TEXT, TEXT, TEXT, BOOLEAN, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
