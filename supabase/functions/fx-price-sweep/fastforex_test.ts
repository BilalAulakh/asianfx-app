// Run: deno test supabase/functions/fx-price-sweep/fastforex_test.ts
//  (or: node --experimental-strip-types supabase/functions/fx-price-sweep/fastforex_test.ts)
import { FF_METALS, parseFfQuotes } from "./fastforex.ts";

function assertEquals(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  expected ${e}\n  actual   ${a}`);
  console.log(`ok - ${msg}`);
}

const now = 1_760_000_000_000;

// Example shape from the fastFOREX docs (/metals/quote).
const metals = {
  quotes: {
    XAUUSD: { bid: "2500.10", ask: "2500.90", mid: "2500.50", tsp: now - 1500 },
    XAGUSD: { bid: "30.10", ask: "30.20", tsp: String(now - 2000) }, // no mid: (bid+ask)/2
    XPTUSD: { bid: "1000", ask: "1001", mid: "1000.5", tsp: now - 60_000 }, // too old
  },
  source: "otc_aggregate",
  ms: 8,
};

assertEquals(
  parseFfQuotes(metals, FF_METALS, now, 15_000),
  { "XAU/USD": 2500.5, "XAG/USD": 30.15 },
  "uses mid, falls back to (bid+ask)/2, drops quotes older than the limit",
);

assertEquals(
  parseFfQuotes({ quotes: { XAUUSD: { bid: "2500", ask: "2499", tsp: now } } }, FF_METALS, now, 15_000),
  {},
  "drops a crossed quote (ask < bid)",
);

assertEquals(
  parseFfQuotes({ quotes: { XAUUSD: { bid: "2500", ask: "2501", mid: "9999", tsp: now } } }, FF_METALS, now, 15_000),
  { "XAU/USD": 2500.5 },
  "ignores a mid outside bid/ask",
);

assertEquals(parseFfQuotes(null, FF_METALS, now, 15_000), {}, "survives an empty body");
assertEquals(parseFfQuotes({ error: "plan" }, FF_METALS, now, 15_000), {}, "survives an error body");
