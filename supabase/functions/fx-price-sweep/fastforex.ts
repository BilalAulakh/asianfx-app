// fastFOREX (https://www.fastforex.io) live quotes for fx-price-sweep.
//
//   GET /metals/quote?instruments=XAUUSD,XAGUSD   (Premium plan)
//   GET /fx/quote?pairs=EURUSD,GBPUSD             (Extra / Premium plan)
//   header X-API-Key: <FASTFOREX_API_KEY>
//
// Both answer { quotes: { XAUUSD: { bid, ask, mid?, tsp }, ... } } with tsp in
// epoch milliseconds. Only the mid is used: the broker's own spread is applied
// afterwards (toQuote in index.ts).

/// App symbol -> fastFOREX metals instrument.
export const FF_METALS: Record<string, string> = {
  "XAU/USD": "XAUUSD",
  "XAG/USD": "XAGUSD",
  "XPT/USD": "XPTUSD",
};

/// App symbol -> fastFOREX FX pair (the most traded pairs only, to stay inside
/// the plan's monthly call allowance; other pairs keep the free source).
export const FF_FX: Record<string, string> = {
  "EUR/USD": "EURUSD",
  "GBP/USD": "GBPUSD",
  "USD/JPY": "USDJPY",
};

const BASE = "https://api.fastforex.io";

interface FfQuote {
  bid?: string | number;
  ask?: string | number;
  mid?: string | number;
  tsp?: string | number;
}

/// Mid prices from a fastFOREX quotes response, keyed by app symbol. A quote
/// is dropped when it is missing, not positive, crossed (ask < bid) or older
/// than `maxAgeMs` by its own timestamp.
export function parseFfQuotes(
  body: unknown,
  appToFf: Record<string, string>,
  nowMs: number,
  maxAgeMs: number,
): Record<string, number> {
  const quotes = (body as { quotes?: Record<string, FfQuote> } | null)?.quotes;
  const out: Record<string, number> = {};
  if (!quotes || typeof quotes !== "object") return out;
  for (const [app, code] of Object.entries(appToFf)) {
    const q = quotes[code];
    if (!q) continue;
    const bid = Number(q.bid);
    const ask = Number(q.ask);
    const tsp = Number(q.tsp);
    if (!(bid > 0) || !(ask >= bid)) continue;
    if (!Number.isFinite(tsp) || nowMs - tsp > maxAgeMs) continue;
    const mid = Number(q.mid);
    out[app] = mid > 0 && mid >= bid && mid <= ask ? mid : (bid + ask) / 2;
  }
  return out;
}

/// Live mids for the requested app symbols that fastFOREX covers. Empty on
/// any failure (no key, plan without the endpoint, network): callers fall back
/// to the free sources.
export async function fastForexMids(
  apiKey: string | undefined,
  kind: "metals" | "fx",
  symbols: string[],
  nowMs: number,
  maxAgeMs: number,
): Promise<Record<string, number>> {
  if (!apiKey) return {};
  const table = kind === "metals" ? FF_METALS : FF_FX;
  const wanted: Record<string, string> = {};
  for (const s of symbols) if (table[s]) wanted[s] = table[s];
  const codes = Object.values(wanted);
  if (codes.length === 0) return {};
  const url = kind === "metals"
    ? `${BASE}/metals/quote?instruments=${codes.join(",")}`
    : `${BASE}/fx/quote?pairs=${codes.join(",")}`;
  try {
    const res = await fetch(url, { headers: { "X-API-Key": apiKey }, signal: AbortSignal.timeout(4000) });
    if (!res.ok) return {};
    return parseFfQuotes(await res.json(), wanted, nowMs, maxAgeMs);
  } catch {
    return {};
  }
}
