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
import {
  matchTransfers,
  USDT_CONTRACT_BASE58,
  verifyUsdtTransfer,
  type SolidityTransaction,
  type SolidityTransactionInfo,
  type VerifiedTransfer,
  type WaitingDeposit,
} from "./tron.ts";

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
