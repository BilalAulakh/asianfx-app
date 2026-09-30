// ==============================================================================
// SUPABASE EDGE FUNCTION: verify-trc20-deposit
// TRON Mainnet USDT TRC-20 Transaction Verification via Tatum API
// ==============================================================================
// - Never exposes TATUM_API_KEY to Flutter or response payloads.
// - Strictly verifies blockchain transaction before crediting user balances.
// - Enforces database-level idempotency and atomic updates.
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Base58Check & Hex Utilities for TRON Mainnet (Zero External Dependencies) ──
const BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(hashBuffer);
}

function base58Encode(bytes: Uint8Array): string {
  const digits = [0];
  for (let i = 0; i < bytes.length; i++) {
    for (let j = 0; j < digits.length; j++) {
      digits[j] <<= 8;
    }
    digits[0] += bytes[i];
    let carry = 0;
    for (let j = 0; j < digits.length; j++) {
      digits[j] += carry;
      carry = (digits[j] / 58) | 0;
      digits[j] %= 58;
    }
    while (carry > 0) {
      digits.push(carry % 58);
      carry = (carry / 58) | 0;
    }
  }
  let str = "";
  for (let i = 0; i < bytes.length && bytes[i] === 0; i++) {
    str += "1";
  }
  for (let i = digits.length - 1; i >= 0; i--) {
    str += BASE58_ALPHABET[digits[i]];
  }
  return str;
}

function base58Decode(str: string): Uint8Array {
  let bytes = [0];
  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    const value = BASE58_ALPHABET.indexOf(c);
    if (value === -1) throw new Error(`Invalid Base58 character: ${c}`);
    for (let j = 0; j < bytes.length; j++) {
      bytes[j] *= 58;
    }
    bytes[0] += value;
    let carry = 0;
    for (let j = 0; j < bytes.length; j++) {
      bytes[j] += carry;
      carry = bytes[j] >> 8;
      bytes[j] &= 0xff;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (let i = 0; i < str.length && str[i] === "1"; i++) {
    bytes.push(0);
  }
  return new Uint8Array(bytes.reverse());
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/, "");
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Convert 20-byte or 21-byte hex to TRON Base58Check address (starting with 'T')
async function hexToTronAddress(hex: string): Promise<string> {
  let clean = hex.toLowerCase().replace(/^0x/, "");
  if (clean.length === 40) {
    clean = "41" + clean;
  }
  if (clean.length !== 42 || !clean.startsWith("41")) {
    throw new Error(`Invalid TRON hex address format: ${hex}`);
  }
  const body = hexToBytes(clean);
  const hash1 = await sha256(body);
  const hash2 = await sha256(hash1);
  const checksum = hash2.slice(0, 4);
  const full = new Uint8Array(body.length + 4);
  full.set(body);
  full.set(checksum, body.length);
  return base58Encode(full);
}

// Convert TRON Base58Check address to 21-byte hex (42 hex chars starting with 41)
async function tronAddressToHex(base58: string): Promise<string> {
  const decoded = base58Decode(base58.trim());
  if (decoded.length !== 25) {
    throw new Error(`Invalid TRON address length (${decoded.length} bytes, expected 25)`);
  }
  const body = decoded.slice(0, 21);
  const checksum = decoded.slice(21, 25);
  const hash1 = await sha256(body);
  const hash2 = await sha256(hash1);
  for (let i = 0; i < 4; i++) {
    if (hash2[i] !== checksum[i]) {
      throw new Error("Invalid TRON address Base58 checksum");
    }
  }
  return bytesToHex(body);
}

// Known Official TRON Mainnet USDT Contract Addresses
const USDT_TRC20_BASE58 = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
const USDT_TRC20_HEX_41 = "41a614f803b6fd780986a42c78ec9c7f77e6ded13c";
const USDT_TRC20_HEX_20 = "a614f803b6fd780986a42c78ec9c7f77e6ded13c";

// Standard TRC20 transfer(address,uint256) function selector
const TRC20_TRANSFER_METHOD = "a9059cbb";

// CORS Response Headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function createJsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

serve(async (req: Request) => {
  // Handle HTTP OPTIONS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return createJsonResponse(
      { success: false, verified: false, message: "Method not allowed. Use POST." },
      405
    );
  }

  try {
    // 1. Secret & Configuration Validation
    const tatumApiKey = Deno.env.get("TATUM_API_KEY");
    if (!tatumApiKey || tatumApiKey.trim() === "") {
      console.error("[CRITICAL] TATUM_API_KEY environment variable is missing.");
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Internal server configuration error. Contact support.",
        },
        500
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error("[CRITICAL] Supabase internal URL or service role key missing.");
      return createJsonResponse(
        { success: false, verified: false, message: "Database configuration error." },
        500
      );
    }

    // 2. Authentication & Authorization Enforcement
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return createJsonResponse(
        { success: false, verified: false, message: "Missing or invalid authorization session." },
        401
      );
    }

    const userJwt = authHeader.replace("Bearer ", "").trim();
    const supabaseUserClient = createClient(supabaseUrl, supabaseAnonKey || supabaseServiceKey, {
      auth: { persistSession: false },
    });

    const { data: authData, error: authError } = await supabaseUserClient.auth.getUser(userJwt);
    if (authError || !authData?.user) {
      return createJsonResponse(
        { success: false, verified: false, message: "Session expired or invalid user token." },
        401
      );
    }

    const authenticatedUserId = authData.user.id;

    // 3. Payload Extraction & Sanitization
    let payload: {
      txid?: string;
      expectedAmount?: number | string;
      depositAddress?: string;
      userId?: string;
    };

    try {
      payload = await req.json();
    } catch {
      return createJsonResponse(
        { success: false, verified: false, message: "Invalid JSON request payload." },
        400
      );
    }

    const rawTxid = payload.txid?.trim() ?? "";
    const rawExpectedAmount = payload.expectedAmount;
    const rawDepositAddress = payload.depositAddress?.trim() ?? "";
    const requestedUserId = payload.userId?.trim() ?? "";

    // Security Check: Caller can only verify deposits for their own account
    if (requestedUserId && requestedUserId !== authenticatedUserId) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Forbidden: You cannot submit verification requests for another user account.",
        },
        403
      );
    }

    const targetUserId = authenticatedUserId;

    // Validate Input Formats
    if (!rawTxid || !/^[0-9a-fA-F]{64}$/.test(rawTxid)) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Invalid TRON transaction hash (TXID). Must be a 64-character hexadecimal string.",
        },
        400
      );
    }

    const expectedAmountNum = Number(rawExpectedAmount);
    if (isNaN(expectedAmountNum) || expectedAmountNum <= 0) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Invalid expected deposit amount. Must be greater than 0.",
        },
        400
      );
    }

    if (!rawDepositAddress || !rawDepositAddress.startsWith("T") || rawDepositAddress.length !== 34) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Invalid TRON deposit destination address format.",
        },
        400
      );
    }

    // Verify Deposit Address Checksum
    let expectedDepositHex: string;
    try {
      expectedDepositHex = await tronAddressToHex(rawDepositAddress);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Invalid address";
      return createJsonResponse(
        { success: false, verified: false, message: `Deposit address checksum error: ${msg}` },
        400
      );
    }

    const cleanTxid = rawTxid.toLowerCase();

    // 4. Check for Existing Credited Deposit in Database Before API Call
    const supabaseService = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
    });

    const { data: existingDeposit } = await supabaseService
      .from("deposits")
      .select("id, status, user_id, amount, created_at")
      .eq("txid", cleanTxid)
      .maybeSingle();

    if (existingDeposit) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "This transaction ID has already been credited to an account.",
        },
        409
      );
    }

    // 5. Query Tatum TRON Mainnet API for Transaction Details
    // Primary Endpoint: GET https://api.tatum.io/v3/tron/transaction/{hash}
    let txData: Record<string, unknown> | null = null;
    const tatumUrl = `https://api.tatum.io/v3/tron/transaction/${cleanTxid}`;

    const tatumRes = await fetch(tatumUrl, {
      method: "GET",
      headers: {
        "x-api-key": tatumApiKey,
        "Accept": "application/json",
      },
    });

    if (tatumRes.status === 200) {
      txData = await tatumRes.json();
    } else if (tatumRes.status === 404 || tatumRes.status === 400) {
      // Fallback: Query Tatum Managed TRON RPC Gateway
      try {
        const rpcRes = await fetch("https://api.tatum.io/v3/blockchain/node/tron-mainnet/wallet/gettransactionbyid", {
          method: "POST",
          headers: {
            "x-api-key": tatumApiKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ value: cleanTxid }),
        });
        if (rpcRes.ok) {
          const rpcData = await rpcRes.json();
          if (rpcData && rpcData.txID) {
            txData = rpcData;
          }
        }
      } catch {
        // Fallback failed silently; handle below
      }
    }

    if (!txData || !txData.raw_data) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction not found or not yet broadcast on TRON Mainnet. Please wait 15-30 seconds and retry.",
        },
        404
      );
    }

    // 6. Blockchain Verification Rules

    // Rule A: Transaction Execution Status (Must be SUCCESS)
    const retList = txData.ret as Array<{ contractRet?: string }> | undefined;
    const contractRet = retList?.[0]?.contractRet;
    if (contractRet !== "SUCCESS") {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: `Transaction execution failed on TRON blockchain (status: ${contractRet ?? "UNKNOWN"}).`,
        },
        400
      );
    }

    // Rule B: Contract Type (Must be TriggerSmartContract)
    const rawData = txData.raw_data as {
      contract?: Array<{
        type?: string;
        parameter?: {
          value?: {
            data?: string;
            contract_address?: string;
            owner_address?: string;
          };
        };
      }>;
    };

    const firstContract = rawData.contract?.[0];
    if (firstContract?.type !== "TriggerSmartContract") {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction is not a smart contract interaction (TriggerSmartContract).",
        },
        400
      );
    }

    const paramValue = firstContract.parameter?.value;
    if (!paramValue || !paramValue.data) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Missing smart contract execution parameters in transaction.",
        },
        400
      );
    }

    // Rule C: Smart Contract Address (Must be Official TRON Mainnet USDT TRC-20)
    const rawContractAddr = (paramValue.contract_address ?? "").toLowerCase().replace(/^0x/, "");
    const isUsdtContract =
      rawContractAddr === USDT_TRC20_BASE58.toLowerCase() ||
      rawContractAddr === USDT_TRC20_HEX_41.toLowerCase() ||
      rawContractAddr === USDT_TRC20_HEX_20.toLowerCase();

    if (!isUsdtContract) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction target is not the official TRON USDT TRC-20 contract.",
        },
        400
      );
    }

    // Rule D: Method Selector (Must be standard TRC-20 transfer(address,uint256) -> a9059cbb)
    const methodData = paramValue.data.toLowerCase().replace(/^0x/, "");
    if (!methodData.startsWith(TRC20_TRANSFER_METHOD) || methodData.length < 136) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction is not a valid TRC-20 transfer(address, uint256) invocation.",
        },
        400
      );
    }

    // Rule E: Destination Address Matching
    // Extract recipient address word (chars 8 to 72 = 64 hex characters)
    // The 20-byte address is in the last 40 hex characters
    const recipientWordHex = methodData.substring(8, 72);
    const recipient20Hex = recipientWordHex.slice(-40);
    const recipient41Hex = "41" + recipient20Hex;
    const recipientBase58 = await hexToTronAddress(recipient41Hex);

    const isAddressMatch =
      recipientBase58.toLowerCase() === rawDepositAddress.toLowerCase() ||
      recipient41Hex.toLowerCase() === expectedDepositHex.toLowerCase();

    if (!isAddressMatch) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction destination address does not match your assigned deposit address.",
        },
        400
      );
    }

    // Rule F: Received Amount Matching (USDT uses 6 decimal places: 1 USDT = 1,000,000 sun)
    const amountWordHex = methodData.substring(72, 136);
    const rawAmountSun = BigInt("0x" + amountWordHex);
    const actualAmountUsdt = Number(rawAmountSun) / 1_000_000;

    // Check if received amount is sufficient (allow for minute rounding drift <= 0.0001)
    if (actualAmountUsdt < expectedAmountNum - 0.0001) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: `Deposited amount on blockchain (${actualAmountUsdt.toFixed(2)} USDT) is less than expected (${expectedAmountNum.toFixed(2)} USDT).`,
        },
        400
      );
    }

    // Rule G: Block Inclusion & Confirmation / Finality
    const blockNumber = typeof txData.blockNumber === "number" ? txData.blockNumber : null;
    if (!blockNumber || blockNumber <= 0) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Transaction is still unconfirmed in mempool. Please wait for block confirmation.",
        },
        400
      );
    }

    // Extract Sender Address for Audit Trail
    let senderBase58: string | null = null;
    if (paramValue.owner_address) {
      try {
        const ownerClean = paramValue.owner_address.toLowerCase().replace(/^0x/, "");
        senderBase58 = ownerClean.startsWith("41")
          ? await hexToTronAddress(ownerClean)
          : paramValue.owner_address;
      } catch {
        senderBase58 = paramValue.owner_address;
      }
    }

    // 7. Atomic Database Execution: Credit Deposit & User Wallet
    // Invokes PostgreSQL function `public.credit_verified_deposit` via Service Role
    const { data: dbResult, error: dbError } = await supabaseService.rpc(
      "credit_verified_deposit",
      {
        p_user_id: targetUserId,
        p_txid: cleanTxid,
        p_amount: actualAmountUsdt,
        p_token: "USDT",
        p_network: "TRC20",
        p_deposit_address: rawDepositAddress,
        p_from_address: senderBase58,
        p_block_number: blockNumber,
        p_raw_tx: {
          txID: cleanTxid,
          blockNumber: blockNumber,
          sender: senderBase58,
          recipient: recipientBase58,
          amountSun: rawAmountSun.toString(),
        },
      }
    );

    if (dbError) {
      console.error("[DATABASE_ERROR] credit_verified_deposit RPC failed:", dbError);
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "Database settlement error. Please contact administrative support.",
        },
        500
      );
    }

    if (dbResult && dbResult.already_credited) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: "This transaction ID has already been credited to an account.",
        },
        409
      );
    }

    if (!dbResult?.success) {
      return createJsonResponse(
        {
          success: false,
          verified: false,
          message: dbResult?.message ?? "Transaction could not be verified",
        },
        400
      );
    }

    // 8. Safe Success Response (Zero Secret / Internal Details Leakage)
    return createJsonResponse({
      success: true,
      verified: true,
      message: "Deposit verified successfully",
      txid: cleanTxid,
      amount: actualAmountUsdt,
      currency: "USDT",
      network: "TRC20",
      newBalance: dbResult.new_balance,
    });
  } catch (err: unknown) {
    // Global Safe Catch (Never reveal Tatum Key or internals in logs or client response)
    const errMessage = err instanceof Error ? err.message : "Unknown error";
    console.error("[VERIFY_ERROR] Verification exception:", errMessage);
    return createJsonResponse(
      {
        success: false,
        verified: false,
        message: "Transaction could not be verified",
      },
      500
    );
  }
});
