// Tests for tron.ts. Runs without Deno or network:
//   node --experimental-strip-types supabase/functions/auto-verify-deposits/tron_test.ts
import {
  base58Decode,
  base58Encode,
  bytesToHex,
  decodeTrc20Transfer,
  hexToTronAddress,
  matchTransfers,
  toMicro,
  tronAddressToHex,
  USDT_CONTRACT_BASE58,
  USDT_CONTRACT_HEX,
  verifyUsdtTransfer,
  type VerifiedTransfer,
} from "./tron.ts";

// Address A as currently configured fails TRON's own Base58Check validation
// (TronGrid /wallet/validateaddress: "Invalid address"), so tests use a valid
// stand-in sender/other-recipient address instead.
const CONFIGURED_ADDRESS_A = "TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV";
const ADDRESS_B = "TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS";
const OTHER = USDT_CONTRACT_BASE58; // any valid Base58Check address

let failures = 0;
let passed = 0;
async function test(name: string, fn: () => Promise<void> | void) {
  try {
    await fn();
    passed++;
    console.log(`ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${name}\n     ${(e as Error).message}`);
  }
}
function eq(actual: unknown, expected: unknown, msg = "") {
  const a = typeof actual === "bigint" ? actual.toString() : JSON.stringify(actual);
  const b = typeof expected === "bigint" ? expected.toString() : JSON.stringify(expected);
  if (a !== b) throw new Error(`${msg} expected ${b}, got ${a}`);
}
async function throws(fn: () => unknown, code: string) {
  try {
    await fn();
  } catch (e) {
    if ((e as Error).message === code) return;
    throw new Error(`expected ${code}, got ${(e as Error).message}`);
  }
  throw new Error(`expected ${code}, nothing thrown`);
}

/** Build transfer(address,uint256) call data for a recipient + micro-USDT amount. */
async function transferData(to: string, micro: bigint, selector = "a9059cbb"): Promise<string> {
  const hex = (await tronAddressToHex(to)).substring(2); // 20 bytes
  return selector + hex.padStart(64, "0") + micro.toString(16).padStart(64, "0");
}

async function tx(opts: { to?: string; micro?: bigint; contract?: string; ret?: string; type?: string; data?: string } = {}) {
  const data = opts.data ?? (await transferData(opts.to ?? ADDRESS_B, opts.micro ?? 98_500_000n));
  return {
    tx: {
      txID: "AB".repeat(32),
      ret: [{ contractRet: opts.ret ?? "SUCCESS" }],
      raw_data: {
        timestamp: 1_700_000_000_000,
        contract: [{
          type: opts.type ?? "TriggerSmartContract",
          parameter: { value: {
            owner_address: await tronAddressToHex(OTHER),
            contract_address: opts.contract ?? USDT_CONTRACT_HEX,
            data,
          } },
        }],
      },
    },
    info: { id: "ab".repeat(32), blockNumber: 66_000_000, blockTimeStamp: 1_700_000_003_000, receipt: { result: "SUCCESS" } },
  };
}

// ── Base58 / hex ──────────────────────────────────────────────────────────────
await test("USDT contract Base58 -> hex", async () => eq(await tronAddressToHex(USDT_CONTRACT_BASE58), USDT_CONTRACT_HEX));
await test("USDT contract hex -> Base58", async () => eq(await hexToTronAddress(USDT_CONTRACT_HEX), USDT_CONTRACT_BASE58));
await test("20-byte hex is accepted (41 prefix added)", async () =>
  eq(await hexToTronAddress(USDT_CONTRACT_HEX.substring(2)), USDT_CONTRACT_BASE58));
await test("configured Address A has an invalid checksum", () => throws(() => tronAddressToHex(CONFIGURED_ADDRESS_A), "INVALID_TRON_CHECKSUM"));
for (const addr of [ADDRESS_B, OTHER]) {
  await test(`round trip ${addr}`, async () => eq(await hexToTronAddress(await tronAddressToHex(addr)), addr));
}
await test("raw Base58 encode/decode round trip", () => {
  const bytes = new Uint8Array([0, 0, 1, 2, 255, 128, 7]);
  eq(bytesToHex(base58Decode(base58Encode(bytes))), bytesToHex(bytes));
});
await test("malformed: bad Base58 character", () => throws(() => tronAddressToHex("T0OIl"), "INVALID_BASE58"));
await test("malformed: wrong checksum", () =>
  throws(() => tronAddressToHex(ADDRESS_B.substring(0, 33) + (ADDRESS_B.endsWith("S") ? "T" : "S")), "INVALID_TRON_CHECKSUM"));
await test("malformed: too short", () => throws(() => tronAddressToHex("TNK1ngQW59"), "INVALID_TRON_ADDRESS"));
await test("malformed: hex not starting with 41", () => throws(() => hexToTronAddress("42" + "00".repeat(20)), "INVALID_TRON_HEX"));

// ── Transfer decoding ────────────────────────────────────────────────────────
await test("decode recipient and amount (6 decimals)", async () => {
  const d = await decodeTrc20Transfer(await transferData(ADDRESS_B, 98_500_000n));
  eq(d.to, ADDRESS_B);
  eq(d.rawAmount, 98_500_000n);
  eq(d.amount, "98.500000");
});
await test("decode 1 micro-USDT", async () => eq((await decodeTrc20Transfer(await transferData(ADDRESS_B, 1n))).amount, "0.000001"));
await test("wrong method selector rejected", async () =>
  throws(async () => decodeTrc20Transfer(await transferData(ADDRESS_B, 1n, "095ea7b3")), "INVALID_TRANSFER_METHOD"));
await test("truncated data rejected", () => throws(() => decodeTrc20Transfer("a9059cbb" + "00".repeat(40)), "INVALID_TRANSFER_DATA"));
await test("non-hex data rejected", () => throws(() => decodeTrc20Transfer("a9059cbbzz"), "INVALID_TRANSFER_DATA"));
await test("dirty address word rejected", async () =>
  throws(() => decodeTrc20Transfer("a9059cbb" + "ff".repeat(32) + "00".repeat(32)), "INVALID_TRANSFER_DATA"));

// ── Full verification ────────────────────────────────────────────────────────
await test("valid transfer to the assigned address passes", async () => {
  const { tx: t, info } = await tx();
  const r = await verifyUsdtTransfer(t, info, ADDRESS_B);
  if (!r.ok) throw new Error(JSON.stringify(r));
  eq(r.transfer.amount, "98.500000");
  eq(r.transfer.from, OTHER);
  eq(r.transfer.block, 66_000_000);
});
await test("not yet confirmed = notFound (keep waiting)", async () => {
  eq(await verifyUsdtTransfer({}, {}, ADDRESS_B), { ok: false, notFound: true });
});
const failCases: Array<[string, Parameters<typeof tx>[0], string]> = [
  ["failed transaction", { ret: "REVERT" }, "TRANSACTION_FAILED"],
  ["not a smart-contract call", { type: "TransferContract" }, "INVALID_CONTRACT_TYPE"],
  ["wrong token contract", { contract: "41" + "11".repeat(20) }, "INVALID_USDT_CONTRACT"],
  ["approve() instead of transfer()", { data: "095ea7b3" + "00".repeat(64) }, "INVALID_TRANSFER_METHOD"],
  ["sent to another address, assigned B", { to: OTHER }, "WRONG_RECIPIENT"],
  ["zero amount", { micro: 0n }, "ZERO_AMOUNT"],
];
for (const [name, opts, reason] of failCases) {
  await test(`rejects: ${name}`, async () => {
    const { tx: t, info } = await tx(opts);
    eq(await verifyUsdtTransfer(t, info, ADDRESS_B), { ok: false, notFound: false, reason });
  });
}

// ── Matching (no TXID from users) ────────────────────────────────────────────
const tr = (txid: string, micro: bigint, ts: number): VerifiedTransfer =>
  ({ txid, to: ADDRESS_B, from: OTHER, amount: "", rawAmount: micro, block: 1, timestampMs: ts });

await test("toMicro parses decimals", () => eq(toMicro("98.5"), 98_500_000n));
await test("exact amount, FIFO", () => {
  const m = matchTransfers(
    [{ id: "d1", createdAtMs: 100, claimed: "100" }, { id: "d2", createdAtMs: 200, claimed: "100" }],
    [tr("t2", 100_000_000n, 400), tr("t1", 100_000_000n, 300)],
  );
  eq(m.get("d1")?.txid, "t1");
  eq(m.get("d2")?.txid, "t2");
});
await test("transfer before the request is never used", () => {
  const m = matchTransfers([{ id: "d1", createdAtMs: 500, claimed: "50" }], [tr("t1", 50_000_000n, 400)]);
  eq(m.size, 0);
});
await test("sole deposit + sole transfer with a different amount is matched (on-chain amount wins)", () => {
  const m = matchTransfers([{ id: "d1", createdAtMs: 100, claimed: "100" }], [tr("t1", 98_500_000n, 300)]);
  eq(m.get("d1")?.txid, "t1");
});
await test("ambiguous different amounts are left for manual review", () => {
  const m = matchTransfers(
    [{ id: "d1", createdAtMs: 100, claimed: "100" }, { id: "d2", createdAtMs: 150, claimed: "70" }],
    [tr("t1", 98_500_000n, 300), tr("t2", 69_000_000n, 310)],
  );
  eq(m.size, 0);
});

console.log(`\n${passed} passed, ${failures} failed`);
if (failures > 0) {
  // deno-lint-ignore no-explicit-any
  (globalThis as any).process?.exit?.(1);
  // deno-lint-ignore no-explicit-any
  (globalThis as any).Deno?.exit?.(1);
}
