// GENERATED single-file copy of supabase/functions/auto-verify-deposits/{tron.ts,index.ts}
// for pasting into the Supabase dashboard editor. DO NOT EDIT: edit the two
// source files and regenerate.

// ==============================================================================
// SUPABASE EDGE FUNCTION: auto-verify-deposits
//
// Automatic approval for company addresses with auto_verify = true (Address B).
// Runs every minute (pg_cron + pg_net, see SECURITY_CHANGES.md).
//
// Users never submit a TXID, so for each auto-verify address the function:
//   1. lists confirmed USDT transfers TO that address since the oldest WAITING
//      request (TronGrid /v1/accounts/{address}/transactions/trc20);
//   2. re-checks every candidate on the SOLIDITY (irreversible) endpoints:
//      /walletsolidity/gettransactionbyid + /walletsolidity/gettransactioninfobyid
//      -> SUCCESS, TriggerSmartContract, official USDT contract, transfer()
//      selector, decoded recipient == deposit_requests.address_used, amount > 0;
//   3. pairs verified transfers with WAITING requests (tron.ts matchTransfers);
//   4. rpc_system_approve_deposit credits the ON-CHAIN amount (idempotent; the
//      RPC re-checks recipient and the max_auto_approve_usd limit);
//   5. otherwise records an attempt, and after 30 minutes / 30 attempts marks
//      the request FAILED (TIMEOUT) so it enters the admin Pending queue.
//
// TronGrid only (no Tatum). Optional secret TRONGRID_API_KEY is sent as the
// TRON-PRO-API-KEY header. On HTTP 429 the run stops and the next minute retries.
// Uses SUPABASE_SERVICE_ROLE_KEY internally; no secret is ever logged.
//
// Deploy:   supabase functions deploy auto-verify-deposits
// Secrets:  TRONGRID_API_KEY (optional), SWEEP_SECRET (shared with fx-price-sweep)
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ==============================================================================
// TRON / USDT-TRC20 helpers for auto-verify-deposits. Pure functions, no I/O,
// so they run under Deno (Edge Function) and Node (tron_test.ts) alike.
// Base58Check helpers ported from the retired Tatum verify-trc20-deposit function.
// ==============================================================================

const BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/// Official USDT (Tether) TRC-20 contract on TRON mainnet.
const USDT_CONTRACT_BASE58 = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
const USDT_CONTRACT_HEX = "41a614f803b6fd780986a42c78ec9c7f77e6ded13c";
/// transfer(address,uint256)
const TRC20_TRANSFER_SELECTOR = "a9059cbb";
const USDT_DECIMALS = 6;

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/i, "");
  if (clean.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(clean)) throw new Error("INVALID_HEX");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base58Encode(bytes: Uint8Array): string {
  const digits = [0];
  for (const byte of bytes) {
    let carry = byte;
    for (let j = 0; j < digits.length; j++) {
      carry += digits[j] << 8;
      digits[j] = carry % 58;
      carry = (carry / 58) | 0;
    }
    while (carry > 0) {
      digits.push(carry % 58);
      carry = (carry / 58) | 0;
    }
  }
  let out = "";
  for (let i = 0; i < bytes.length && bytes[i] === 0; i++) out += "1";
  for (let i = digits.length - 1; i >= 0; i--) out += BASE58_ALPHABET[digits[i]];
  return out;
}

function base58Decode(str: string): Uint8Array {
  const bytes = [0];
  for (const c of str) {
    const value = BASE58_ALPHABET.indexOf(c);
    if (value === -1) throw new Error("INVALID_BASE58");
    let carry = value;
    for (let j = 0; j < bytes.length; j++) {
      carry += bytes[j] * 58;
      bytes[j] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (let i = 0; i < str.length && str[i] === "1"; i++) bytes.push(0);
  return new Uint8Array(bytes.reverse());
}

/// 21-byte hex (41 + 20 bytes) or 20-byte hex -> TRON Base58Check address ("T...").
async function hexToTronAddress(hex: string): Promise<string> {
  let clean = hex.toLowerCase().replace(/^0x/, "");
  if (clean.length === 40) clean = "41" + clean;
  if (clean.length !== 42 || !clean.startsWith("41")) throw new Error("INVALID_TRON_HEX");
  const body = hexToBytes(clean);
  const checksum = (await sha256(await sha256(body))).slice(0, 4);
  const full = new Uint8Array(25);
  full.set(body);
  full.set(checksum, 21);
  return base58Encode(full);
}

/// TRON Base58Check address -> 21-byte hex ("41..."). Verifies the checksum.
async function tronAddressToHex(address: string): Promise<string> {
  const decoded = base58Decode(address.trim());
  if (decoded.length !== 25) throw new Error("INVALID_TRON_ADDRESS");
  const body = decoded.slice(0, 21);
  if (body[0] !== 0x41) throw new Error("INVALID_TRON_ADDRESS");
  const hash = await sha256(await sha256(body));
  for (let i = 0; i < 4; i++) {
    if (hash[i] !== decoded[21 + i]) throw new Error("INVALID_TRON_CHECKSUM");
  }
  return bytesToHex(body);
}

interface DecodedTransfer {
  /** Recipient, Base58 ("T..."). */
  to: string;
  /** Raw integer amount (6 decimals for USDT). */
  rawAmount: bigint;
  /** Human amount as a decimal string with 6 decimals, e.g. "98.500000". */
  amount: string;
}

/// Decode TRC-20 transfer(address,uint256) call data:
/// a9059cbb | 32-byte address word | 32-byte uint256 amount.
async function decodeTrc20Transfer(data: string): Promise<DecodedTransfer> {
  const clean = (data ?? "").toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]*$/.test(clean)) throw new Error("INVALID_TRANSFER_DATA");
  if (!clean.startsWith(TRC20_TRANSFER_SELECTOR)) throw new Error("INVALID_TRANSFER_METHOD");
  if (clean.length < 8 + 64 + 64) throw new Error("INVALID_TRANSFER_DATA");
  const addressWord = clean.substring(8, 72);
  const amountWord = clean.substring(72, 136);
  // An address word is 12 zero bytes + 20 address bytes (TRON may put 41 in byte 12).
  const prefix = addressWord.substring(0, 22);
  if (!/^0{22}$/.test(prefix) || !/^(00|41)$/.test(addressWord.substring(22, 24))) {
    throw new Error("INVALID_TRANSFER_DATA");
  }
  const to = await hexToTronAddress("41" + addressWord.substring(24));
  const rawAmount = BigInt("0x" + amountWord);
  return { to, rawAmount, amount: formatUnits(rawAmount, USDT_DECIMALS) };
}

function formatUnits(raw: bigint, decimals: number): string {
  const neg = raw < 0n;
  const abs = neg ? -raw : raw;
  const base = 10n ** BigInt(decimals);
  const whole = abs / base;
  const frac = (abs % base).toString().padStart(decimals, "0");
  return `${neg ? "-" : ""}${whole}.${frac}`;
}

/** A transfer that passed every on-chain check. */
interface VerifiedTransfer {
  txid: string;
  to: string;
  from: string;
  amount: string;
  rawAmount: bigint;
  block: number;
  timestampMs: number;
}

/** Definitive verification failures (move the deposit to manual review). */
type VerifyFailure =
  | "TRANSACTION_FAILED"
  | "INVALID_CONTRACT_TYPE"
  | "INVALID_USDT_CONTRACT"
  | "INVALID_TRANSFER_METHOD"
  | "INVALID_TRANSFER_DATA"
  | "WRONG_RECIPIENT"
  | "ZERO_AMOUNT";

type VerifyResult =
  | { ok: true; transfer: VerifiedTransfer }
  | { ok: false; notFound: true }
  | { ok: false; notFound: false; reason: VerifyFailure };

// Minimal shapes of TronGrid /walletsolidity responses.
interface SolidityTransaction {
  txID?: string;
  ret?: Array<{ contractRet?: string }>;
  raw_data?: {
    timestamp?: number;
    contract?: Array<{
      type?: string;
      parameter?: { value?: { owner_address?: string; contract_address?: string; data?: string } };
    }>;
  };
}
interface SolidityTransactionInfo {
  id?: string;
  blockNumber?: number;
  blockTimeStamp?: number;
  result?: string;
  receipt?: { result?: string };
}

/// Apply every check to a CONFIRMED transaction (walletsolidity endpoints).
/// `expectedTo` must come from the database (deposit_requests.address_used).
async function verifyUsdtTransfer(
  tx: SolidityTransaction | null | undefined,
  info: SolidityTransactionInfo | null | undefined,
  expectedTo: string,
): Promise<VerifyResult> {
  // Solidity endpoints return {} until the transaction is irreversible.
  if (!tx || !tx.txID || !info || !info.id || typeof info.blockNumber !== "number") {
    return { ok: false, notFound: true };
  }

  const fail = (reason: VerifyFailure): VerifyResult => ({ ok: false, notFound: false, reason });

  if (tx.ret?.[0]?.contractRet !== "SUCCESS") return fail("TRANSACTION_FAILED");
  if (info.result === "FAILED" || (info.receipt?.result && info.receipt.result !== "SUCCESS")) {
    return fail("TRANSACTION_FAILED");
  }

  const contract = tx.raw_data?.contract?.[0];
  if (contract?.type !== "TriggerSmartContract") return fail("INVALID_CONTRACT_TYPE");

  const value = contract.parameter?.value ?? {};
  if ((value.contract_address ?? "").toLowerCase() !== USDT_CONTRACT_HEX) return fail("INVALID_USDT_CONTRACT");

  let decoded: DecodedTransfer;
  try {
    decoded = await decodeTrc20Transfer(value.data ?? "");
  } catch (e) {
    return fail((e as Error).message === "INVALID_TRANSFER_METHOD" ? "INVALID_TRANSFER_METHOD" : "INVALID_TRANSFER_DATA");
  }

  if (decoded.to !== expectedTo.trim()) return fail("WRONG_RECIPIENT");
  if (decoded.rawAmount <= 0n) return fail("ZERO_AMOUNT");

  let from: string;
  try {
    from = await hexToTronAddress(value.owner_address ?? "");
  } catch {
    return fail("INVALID_TRANSFER_DATA");
  }

  return {
    ok: true,
    transfer: {
      txid: tx.txID.toLowerCase(),
      to: decoded.to,
      from,
      amount: decoded.amount,
      rawAmount: decoded.rawAmount,
      block: info.blockNumber,
      timestampMs: info.blockTimeStamp ?? tx.raw_data?.timestamp ?? 0,
    },
  };
}

// ------------------------------------------------------------------------------
// Matching transfers to deposit requests (no TXID is collected from users).
// ------------------------------------------------------------------------------

interface WaitingDeposit {
  id: string;
  createdAtMs: number;
  /** Claimed amount, decimal string. */
  claimed: string;
}

/** Amount in micro-USDT (6 dp) from a decimal string, for exact comparison. */
function toMicro(amount: string): bigint {
  const [whole, frac = ""] = amount.trim().split(".");
  if (!/^\d+$/.test(whole) || !/^\d*$/.test(frac)) throw new Error("INVALID_AMOUNT");
  return BigInt(whole) * 1_000_000n + BigInt((frac + "000000").substring(0, 6));
}

/// Pair verified transfers with waiting deposits on ONE address.
///
///  1. Exact amount (to the cent): oldest deposit gets the oldest transfer that
///     arrived after it was created. Equal amounts are interchangeable, so FIFO
///     pairing credits every sender exactly what they sent.
///  2. Otherwise a deposit is matched to a different amount only when it is the
///     sole unmatched deposit AND exactly one unmatched transfer arrived after it
///     (claimed 100, sent 98.50 -> 98.50 credited). Anything more ambiguous is
///     left to time out into manual review.
function matchTransfers(
  deposits: WaitingDeposit[],
  transfers: VerifiedTransfer[],
): Map<string, VerifiedTransfer> {
  const result = new Map<string, VerifiedTransfer>();
  const used = new Set<string>();
  const ds = [...deposits].sort((a, b) => a.createdAtMs - b.createdAtMs);
  const ts = [...transfers].sort((a, b) => a.timestampMs - b.timestampMs);
  const cents = (micro: bigint) => micro / 10_000n;

  for (const d of ds) {
    const want = cents(toMicro(d.claimed));
    const t = ts.find((x) => !used.has(x.txid) && x.timestampMs >= d.createdAtMs && cents(x.rawAmount) === want);
    if (t) {
      result.set(d.id, t);
      used.add(t.txid);
    }
  }

  const unmatched = ds.filter((d) => !result.has(d.id));
  if (unmatched.length === 1) {
    const d = unmatched[0];
    const candidates = ts.filter((x) => !used.has(x.txid) && x.timestampMs >= d.createdAtMs);
    if (candidates.length === 1) result.set(d.id, candidates[0]);
  }
  return result;
}

const TRONGRID = "https://api.trongrid.io";
const MAX_DEPOSITS_PER_RUN = 50;
const MAX_CANDIDATES_PER_ADDRESS = 30;
const TIMEOUT_MS = 30 * 60 * 1000;
const MAX_ATTEMPTS = 30;
/** Listing starts this long before the oldest request (clock skew between the app and the chain). */
const LOOKBACK_MS = 60 * 1000;

class RateLimited extends Error {}
class Unavailable extends Error {}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function tronHeaders(): HeadersInit {
  const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json" };
  const key = Deno.env.get("TRONGRID_API_KEY");
  if (key) headers["TRON-PRO-API-KEY"] = key;
  return headers;
}

async function tronFetch(path: string, init: RequestInit = {}): Promise<unknown> {
  let res: Response;
  try {
    res = await fetch(`${TRONGRID}${path}`, {
      ...init,
      headers: tronHeaders(),
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new Unavailable("network");
  }
  if (res.status === 429) throw new RateLimited("429");
  if (!res.ok) throw new Unavailable(`http ${res.status}`);
  return await res.json();
}

const solidityPost = (path: string, txid: string) =>
  tronFetch(path, { method: "POST", body: JSON.stringify({ value: txid }) });

interface DepositRow {
  id: string;
  address_used: string;
  amount_claimed: number | string;
  created_at: string;
  verification_attempts: number;
}

serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ success: false, message: "Function is not configured." }, 500);

  const sweepSecret = Deno.env.get("SWEEP_SECRET");
  if (sweepSecret && req.headers.get("x-sweep-secret") !== sweepSecret) {
    return json({ success: false, message: "Forbidden." }, 403);
  }

  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: waiting, error } = await db
    .from("deposit_requests")
    .select("id, address_used, amount_claimed, created_at, verification_attempts")
    .eq("status", "PENDING")
    .eq("verification_status", "WAITING")
    .order("created_at", { ascending: true })
    .limit(MAX_DEPOSITS_PER_RUN);
  if (error) return json({ success: false, stage: "load", message: error.message }, 500);

  const rows = (waiting ?? []) as DepositRow[];
  const summary = { waiting: rows.length, approved: 0, failed: 0, retried: 0, rate_limited: false, errors: 0 };
  if (rows.length === 0) return json({ success: true, ...summary });

  const byAddress = new Map<string, DepositRow[]>();
  for (const r of rows) {
    if (!r.address_used) continue;
    byAddress.set(r.address_used, [...(byAddress.get(r.address_used) ?? []), r]);
  }

  const handled = new Set<string>();

  try {
    for (const [address, deposits] of byAddress) {
      const oldest = Math.min(...deposits.map((d) => Date.parse(d.created_at)));

      // 1. Confirmed USDT transfers into this address since the oldest request.
      const list = await tronFetch(
        `/v1/accounts/${address}/transactions/trc20?only_to=true&only_confirmed=true&limit=200` +
          `&contract_address=${USDT_CONTRACT_BASE58}&min_timestamp=${oldest - LOOKBACK_MS}&order_by=block_timestamp,asc`,
      ) as { data?: Array<{ transaction_id?: string }> };
      let txids = [...new Set((list.data ?? []).map((t) => (t.transaction_id ?? "").toLowerCase()).filter(Boolean))];

      // Never reuse a transfer that already settled a deposit.
      if (txids.length > 0) {
        const { data: used } = await db.from("deposit_requests").select("txid").in("txid", txids);
        const usedSet = new Set((used ?? []).map((u: { txid: string }) => u.txid.toLowerCase()));
        txids = txids.filter((t) => !usedSet.has(t)).slice(0, MAX_CANDIDATES_PER_ADDRESS);
      }

      // 2. Re-verify each candidate on the irreversible (solidity) endpoints.
      const verified: VerifiedTransfer[] = [];
      for (const txid of txids) {
        const tx = await solidityPost("/walletsolidity/gettransactionbyid", txid) as SolidityTransaction;
        const info = await solidityPost("/walletsolidity/gettransactioninfobyid", txid) as SolidityTransactionInfo;
        const result = await verifyUsdtTransfer(tx, info, address);
        if (result.ok) verified.push(result.transfer);
        // notFound: not irreversible yet -> picked up next run.
        // definitive failure: not a valid USDT payment to this address -> ignored.
      }

      // 3. Pair transfers with requests and settle.
      const waitingDeposits: WaitingDeposit[] = deposits.map((d) => ({
        id: d.id,
        createdAtMs: Date.parse(d.created_at),
        claimed: String(d.amount_claimed),
      }));
      const matches = matchTransfers(waitingDeposits, verified);

      for (const [depositId, t] of matches) {
        const { data: res, error: rpcErr } = await db.rpc("rpc_system_approve_deposit", {
          p_deposit_id: depositId,
          p_txid: t.txid,
          p_onchain_amount: t.amount,
          p_onchain_to: t.to,
          p_onchain_from: t.from,
          p_block: t.block,
        });
        handled.add(depositId);
        if (rpcErr) {
          summary.errors++;
          continue;
        }
        const status = (res as { status?: string } | null)?.status;
        if (status === "success") summary.approved++;
        else if (status === "failed") summary.failed++;
      }
    }
  } catch (e) {
    if (e instanceof RateLimited) {
      // Back off: stop this run; the next scheduled run retries.
      summary.rate_limited = true;
    } else if (!(e instanceof Unavailable)) {
      summary.errors++;
    }
    // Temporary TronGrid failure: fall through and only record attempts.
  }

  // 4. Everything not settled: record an attempt, or time out into manual review.
  const now = Date.now();
  for (const d of rows) {
    if (handled.has(d.id)) continue;
    const timedOut = now - Date.parse(d.created_at) >= TIMEOUT_MS || d.verification_attempts + 1 >= MAX_ATTEMPTS;
    const { error: markErr } = await db.rpc("rpc_system_mark_verification", {
      p_deposit_id: d.id,
      p_result: timedOut ? "FAILED" : "RETRY",
      p_error: timedOut ? "TIMEOUT" : null,
    });
    if (markErr) summary.errors++;
    else if (timedOut) summary.failed++;
    else summary.retried++;
  }

  return json({ success: true, ...summary });
});
