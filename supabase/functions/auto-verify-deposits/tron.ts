// ==============================================================================
// TRON / USDT-TRC20 helpers for auto-verify-deposits. Pure functions, no I/O,
// so they run under Deno (Edge Function) and Node (tron_test.ts) alike.
// Base58Check helpers ported from the retired Tatum verify-trc20-deposit function.
// ==============================================================================

const BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/// Official USDT (Tether) TRC-20 contract on TRON mainnet.
export const USDT_CONTRACT_BASE58 = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
export const USDT_CONTRACT_HEX = "41a614f803b6fd780986a42c78ec9c7f77e6ded13c";
/// transfer(address,uint256)
export const TRC20_TRANSFER_SELECTOR = "a9059cbb";
export const USDT_DECIMALS = 6;

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/i, "");
  if (clean.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(clean)) throw new Error("INVALID_HEX");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  return out;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function base58Encode(bytes: Uint8Array): string {
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

export function base58Decode(str: string): Uint8Array {
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
export async function hexToTronAddress(hex: string): Promise<string> {
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
export async function tronAddressToHex(address: string): Promise<string> {
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

export interface DecodedTransfer {
  /** Recipient, Base58 ("T..."). */
  to: string;
  /** Raw integer amount (6 decimals for USDT). */
  rawAmount: bigint;
  /** Human amount as a decimal string with 6 decimals, e.g. "98.500000". */
  amount: string;
}

/// Decode TRC-20 transfer(address,uint256) call data:
/// a9059cbb | 32-byte address word | 32-byte uint256 amount.
export async function decodeTrc20Transfer(data: string): Promise<DecodedTransfer> {
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

export function formatUnits(raw: bigint, decimals: number): string {
  const neg = raw < 0n;
  const abs = neg ? -raw : raw;
  const base = 10n ** BigInt(decimals);
  const whole = abs / base;
  const frac = (abs % base).toString().padStart(decimals, "0");
  return `${neg ? "-" : ""}${whole}.${frac}`;
}

/** A transfer that passed every on-chain check. */
export interface VerifiedTransfer {
  txid: string;
  to: string;
  from: string;
  amount: string;
  rawAmount: bigint;
  block: number;
  timestampMs: number;
}

/** Definitive verification failures (move the deposit to manual review). */
export type VerifyFailure =
  | "TRANSACTION_FAILED"
  | "INVALID_CONTRACT_TYPE"
  | "INVALID_USDT_CONTRACT"
  | "INVALID_TRANSFER_METHOD"
  | "INVALID_TRANSFER_DATA"
  | "WRONG_RECIPIENT"
  | "ZERO_AMOUNT";

export type VerifyResult =
  | { ok: true; transfer: VerifiedTransfer }
  | { ok: false; notFound: true }
  | { ok: false; notFound: false; reason: VerifyFailure };

// Minimal shapes of TronGrid /walletsolidity responses.
export interface SolidityTransaction {
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
export interface SolidityTransactionInfo {
  id?: string;
  blockNumber?: number;
  blockTimeStamp?: number;
  result?: string;
  receipt?: { result?: string };
}

/// Apply every check to a CONFIRMED transaction (walletsolidity endpoints).
/// `expectedTo` must come from the database (deposit_requests.address_used).
export async function verifyUsdtTransfer(
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

export interface WaitingDeposit {
  id: string;
  createdAtMs: number;
  /** Claimed amount, decimal string. */
  claimed: string;
}

/** Amount in micro-USDT (6 dp) from a decimal string, for exact comparison. */
export function toMicro(amount: string): bigint {
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
export function matchTransfers(
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
