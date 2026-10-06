-- ##############################################################################
--  APPLY_DEPOSIT_FIX.sql  —  Supabase SQL Editor mein paste karein aur Run karein.
--  Dobara chalana bhi safe hai.
--
--  1. TXID optional: "a TRON transaction ID must be 64 hexadecimal characters"
--     wala error khatam (copy of 20261005000000_deposit_txid_optional.sql)
--  2. Company deposit address set: "deposits are not configured yet" khatam
-- ##############################################################################

-- ==============================================================================
-- Manual deposits: TXID becomes optional, payment screenshot becomes required.
--
-- The deposit form no longer asks for a transaction hash. The admin verifies a
-- claim from the screenshot (and the company wallet's transfers on Tronscan).
--   * deposit_requests.txid is nullable. The format CHECK and the unique index
--     on lower(txid) both still apply when a TXID is given (NULLs pass/are distinct).
--   * rpc_submit_deposit_request: TXID validated + de-duplicated only when
--     present; p_proof_path is mandatory.
-- ==============================================================================

ALTER TABLE public.deposit_requests ALTER COLUMN txid DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.rpc_submit_deposit_request(
    p_amount       NUMERIC,
    p_txid         TEXT,
    p_from_address TEXT DEFAULT NULL,
    p_proof_path   TEXT DEFAULT NULL,
    p_request_id   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid        TEXT;
    v_cfg        public.broker_config;
    v_txid       TEXT;
    v_from       TEXT;
    v_proof      TEXT;
    v_pending    INTEGER;
    v_row        public.deposit_requests;
    v_constraint TEXT;
BEGIN
    v_uid := public.fx_require_user_id();

    -- ---- Idempotency: a retried submit returns the row it already created.
    IF p_request_id IS NOT NULL THEN
        SELECT * INTO v_row FROM public.deposit_requests
        WHERE user_id = v_uid AND request_id = p_request_id;
        IF FOUND THEN
            RETURN jsonb_build_object('status', 'duplicate',
                                      'deposit', public.fx_deposit_public_json(v_row));
        END IF;
    END IF;

    SELECT * INTO v_cfg FROM public.broker_config WHERE id = 1;
    IF v_cfg.deposit_address_trc20 IS NULL THEN
        RAISE EXCEPTION 'DEPOSITS_DISABLED: deposits are not configured yet. Please contact support.'
            USING ERRCODE = '22023';
    END IF;

    -- ---- Optional TXID: when given, a TRON transaction hash is exactly 64 hex characters.
    v_txid := NULLIF(lower(btrim(COALESCE(p_txid, ''))), '');
    IF v_txid IS NOT NULL AND v_txid !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'BAD_TXID: a TRON transaction ID must be 64 hexadecimal characters'
            USING ERRCODE = '22023';
    END IF;

    -- ---- Amount
    IF p_amount IS NULL OR p_amount < v_cfg.min_deposit_usd THEN
        RAISE EXCEPTION 'AMOUNT_TOO_SMALL: the minimum deposit is % USD', v_cfg.min_deposit_usd
            USING ERRCODE = '22023';
    END IF;
    IF p_amount >= 100000000000000 THEN
        RAISE EXCEPTION 'BAD_AMOUNT: deposit amount is out of range' USING ERRCODE = '22023';
    END IF;

    -- ---- Optional sender address
    v_from := NULLIF(btrim(COALESCE(p_from_address, '')), '');
    IF v_from IS NOT NULL AND v_from !~ '^T[1-9A-HJ-NP-Za-km-z]{33}$' THEN
        RAISE EXCEPTION 'BAD_ADDRESS: the sender address is not a valid TRON (TRC-20) address'
            USING ERRCODE = '22023';
    END IF;

    -- ---- Required proof: must be an object inside the caller's own folder.
    v_proof := NULLIF(btrim(COALESCE(p_proof_path, '')), '');
    IF v_proof IS NULL THEN
        RAISE EXCEPTION 'PROOF_REQUIRED: please attach a screenshot of your payment'
            USING ERRCODE = '22023';
    END IF;
    IF left(v_proof, length(v_uid) + 1) <> v_uid || '/'
       OR position('..' IN v_proof) > 0
       OR length(v_proof) > 512
    THEN
        RAISE EXCEPTION 'BAD_PROOF_PATH: the payment proof must be uploaded to your own folder'
            USING ERRCODE = '42501';
    END IF;

    -- Serialise submissions per user so the pending cap below is race-free.
    PERFORM pg_advisory_xact_lock(hashtext('fx_deposit_request:' || v_uid));

    -- ---- A TXID (when given) can never be claimed twice — not even after a
    --      rejection — and never if the legacy Tatum pipeline already credited it.
    IF v_txid IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM public.deposit_requests WHERE lower(txid) = v_txid) THEN
            RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been submitted'
                USING ERRCODE = '23505';
        END IF;
        IF to_regclass('public.deposits') IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM public.deposits WHERE lower(txid) = v_txid) THEN
                RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been credited'
                    USING ERRCODE = '23505';
            END IF;
        END IF;
    END IF;

    -- ---- Anti-spam
    SELECT COUNT(*) INTO v_pending FROM public.deposit_requests
    WHERE user_id = v_uid AND status = 'PENDING';
    IF v_pending >= 5 THEN
        RAISE EXCEPTION 'TOO_MANY_PENDING: you already have % deposits awaiting review', v_pending
            USING ERRCODE = '22023';
    END IF;

    BEGIN
        INSERT INTO public.deposit_requests
            (user_id, amount_claimed, txid, from_address, deposit_address, proof_path, request_id)
        VALUES
            (v_uid, ROUND(p_amount, 4), v_txid, v_from, v_cfg.deposit_address_trc20, v_proof, p_request_id)
        RETURNING * INTO v_row;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'uq_deposit_requests_request' THEN
            SELECT * INTO v_row FROM public.deposit_requests
            WHERE user_id = v_uid AND request_id = p_request_id;
            RETURN jsonb_build_object('status', 'duplicate',
                                      'deposit', public.fx_deposit_public_json(v_row));
        END IF;
        RAISE EXCEPTION 'TXID_ALREADY_USED: this transaction ID has already been submitted'
            USING ERRCODE = '23505';
    END;

    RETURN jsonb_build_object('status', 'success',
                              'deposit', public.fx_deposit_public_json(v_row));
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_submit_deposit_request(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_submit_deposit_request(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ------------------------------------------------------------------------------
-- Company deposit address (same as AppConstants.usdtTrc20DepositAddress)
-- ------------------------------------------------------------------------------
UPDATE public.broker_config
   SET deposit_address_trc20 = 'TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV',
       updated_at = NOW()
 WHERE id = 1;

-- Make PostgREST see the changes immediately.
NOTIFY pgrst, 'reload schema';

-- Check: one row with the address above.
SELECT id, deposit_address_trc20, min_deposit_usd FROM public.broker_config WHERE id = 1;
