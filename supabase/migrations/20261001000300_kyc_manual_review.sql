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
