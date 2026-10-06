// ==============================================================================
// SUPABASE EDGE FUNCTION: fx-price-sweep
//
// The ONLY source of execution prices, and the offline half of the trading
// engine. Run it every minute:
//
//   1. Pull live prices (Binance for crypto, Yahoo Finance for FX / metals /
//      energy / indices / stocks).
//   2. Drop any price whose source timestamp is older than MAX_SOURCE_AGE_S
//      (market closed, feed frozen). No price -> the quote goes stale -> the
//      RPCs answer NO_QUOTE instead of filling on an old price.
//   3. Apply each instrument's dealer markup x broker_config.spread_multiplier.
//   4. rpc_publish_quotes  -> market_quotes with source='publisher'.
//   5. rpc_sweep_accounts  -> SL/TP, pending triggers, stop-out, swap.
//
// Uses the SERVICE ROLE key, which exists only inside this function.
//
// Deploy:   supabase functions deploy fx-price-sweep
// Secrets:  supabase secrets set SWEEP_SECRET=<random string>   (recommended)
//           -> callers must send header  x-sweep-secret: <random string>
// Schedule: every minute, e.g. with pg_cron + pg_net:
//   select cron.schedule('fx-price-sweep', '* * * * *', $$
//     select net.http_post(
//       url     := 'https://<project-ref>.supabase.co/functions/v1/fx-price-sweep',
//       headers := jsonb_build_object(
//                    'Authorization', 'Bearer <anon-or-service-key>',
//                    'x-sweep-secret', '<random string>'),
//       body    := '{}'::jsonb);
//   $$);
// ==============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface Instrument {
  symbol: string;
  category: string;
  base_currency: string;
  quote_currency: string;
  digits: number;
  spread_markup_points: number;
  trading_enabled: boolean;
}

interface Quote {
  bid: string;
  ask: string;
  rate: string;
}

/// A price older than this (by the SOURCE's own timestamp) is not published.
const MAX_SOURCE_AGE_S = Number(Deno.env.get("MAX_SOURCE_AGE_S") ?? "300");
const YAHOO_CONCURRENCY = 8;

// Spot metals come from gold-api.com (real-time spot, timestamped). Yahoo only
// offers COMEX futures (GC=F / SI=F / PL=F) for these, which are delayed ~10
// minutes — always failing MAX_SOURCE_AGE_S — and priced ~$20 above spot.
const SPOT_METAL: Record<string, string> = {
  "XAU/USD": "XAU", "XAG/USD": "XAG", "XPT/USD": "XPT",
};

const YAHOO_SYMBOL: Record<string, string> = {
  "WTI/USD": "CL=F", "BRENT/USD": "BZ=F", "NGAS/USD": "NG=F",
  "US30/USD": "^DJI", "NAS100/USD": "^IXIC", "SPX500/USD": "^GSPC",
  "GER40/EUR": "^GDAXI", "UK100/GBP": "^FTSE", "JP225/USD": "^N225",
  "AAPL/USD": "AAPL", "NVDA/USD": "NVDA", "TSLA/USD": "TSLA",
  "AMZN/USD": "AMZN", "MSFT/USD": "MSFT", "GOOGL/USD": "GOOGL",
};

const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function fetchJson(url: string, ms = 8000): Promise<unknown | null> {
  try {
    const res = await fetch(url, { headers: { "User-Agent": BROWSER_UA }, signal: AbortSignal.timeout(ms) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/// Yahoo symbol for an instrument: explicit map, else BASEQUOTE=X for FX pairs.
function yahooSymbolFor(inst: Instrument): string | null {
  if (YAHOO_SYMBOL[inst.symbol]) return YAHOO_SYMBOL[inst.symbol];
  if (inst.category === "forex") return `${inst.base_currency}${inst.quote_currency}=X`;
  return null;
}

/// Live mid from Yahoo, only if the source says it traded recently.
async function yahooMid(yahooSymbol: string, nowS: number): Promise<number | null> {
  const data = await fetchJson(
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(yahooSymbol)}?interval=1m&range=1d`,
  ) as { chart?: { result?: Array<{ meta?: Record<string, number> }> } } | null;
  const meta = data?.chart?.result?.[0]?.meta;
  const price = meta?.regularMarketPrice;
  const at = meta?.regularMarketTime;
  if (typeof price !== "number" || price <= 0) return null;
  // No timestamp, or too old (closed market / frozen feed): do not publish.
  if (typeof at !== "number" || nowS - at > MAX_SOURCE_AGE_S) return null;
  return price;
}

/// New York offset from UTC in hours (-4 EDT: 2nd Sun Mar 07:00Z .. 1st Sun Nov 06:00Z, else -5).
function newYorkOffsetHours(d: Date): number {
  const y = d.getUTCFullYear();
  const nthSunday = (month: number, n: number) => {
    const firstDow = new Date(Date.UTC(y, month, 1)).getUTCDay(); // 0 = Sun
    return 1 + ((7 - firstDow) % 7) + (n - 1) * 7;
  };
  const dstStart = Date.UTC(y, 2, nthSunday(2, 2), 7);
  const dstEnd = Date.UTC(y, 10, nthSunday(10, 1), 6);
  const t = d.getTime();
  return t >= dstStart && t < dstEnd ? -4 : -5;
}

/// Spot metals trade Sun 18:00 -> Fri 17:00 New York, with a daily 17:00-18:00 break.
/// Same rule as the app's FxSession, so the server never publishes a weekend price.
function metalsMarketOpen(now: Date): boolean {
  const ny = new Date(now.getTime() + newYorkOffsetHours(now) * 3600_000);
  const dow = ny.getUTCDay(); // 0 = Sun .. 6 = Sat
  const hour = ny.getUTCHours();
  if (dow === 6) return false;                 // Saturday
  if (dow === 0 && hour < 18) return false;    // Sunday before the open
  if (dow === 5 && hour >= 17) return false;   // Friday after the close
  if (hour === 17) return false;               // daily maintenance break
  return true;
}

/// Live spot mids for metals, only if the source timestamp is recent.
async function spotMetalMids(symbols: string[], nowS: number): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  if (symbols.length === 0 || !metalsMarketOpen(new Date(nowS * 1000))) return out;
  await Promise.all(symbols.map(async (sym) => {
    const code = SPOT_METAL[sym];
    const data = await fetchJson(`https://api.gold-api.com/price/${code}`) as
      { price?: number; updatedAt?: string } | null;
    const price = data?.price;
    const at = data?.updatedAt ? Math.floor(Date.parse(data.updatedAt) / 1000) : NaN;
    if (typeof price !== "number" || !(price > 0)) return;
    if (!Number.isFinite(at) || nowS - at > MAX_SOURCE_AGE_S) return;

    // gold-api.com refreshes only every ~30 s in $0.50 steps. Between its
    // updates, carry gold forward with PAX Gold's second-by-second move on
    // Binance: spot + (PAXG now - PAXG at the spot's timestamp). The level stays
    // anchored to spot (PAXG's own premium cancels out); only the movement
    // comes from PAXG. Without a PAXG reading the plain spot price is used.
    const tracker = PAXG_TRACKED[sym];
    if (tracker) {
      const [then, now] = await Promise.all([paxgCloseAt(at), paxgCloseAt(nowS)]);
      if (then !== null && now !== null) {
        out[sym] = price + (now - then);
        return;
      }
    }
    out[sym] = price;
  }));
  return out;
}

/// Metals whose spot price is carried forward between gold-api updates by a Binance token.
const PAXG_TRACKED: Record<string, string> = { "XAU/USD": "PAXGUSDT" };

/// Last PAXG/USDT trade price at or before `atS` (unix seconds), from 1-second klines.
async function paxgCloseAt(atS: number): Promise<number | null> {
  const data = await fetchJson(
    `https://api.binance.com/api/v3/klines?symbol=PAXGUSDT&interval=1s` +
      `&startTime=${(atS - 120) * 1000}&endTime=${atS * 1000 + 999}&limit=1000`,
  ) as Array<[number, string, string, string, string]> | null;
  if (!Array.isArray(data) || data.length === 0) return null;
  const close = Number(data[data.length - 1][4]);
  return Number.isFinite(close) && close > 0 ? close : null;
}

async function binanceMids(symbols: string[]): Promise<Record<string, number>> {
  if (symbols.length === 0) return {};
  const pairs = symbols.map((s) => `"${s.split("/")[0]}USDT"`).join(",");
  const data = await fetchJson(
    `https://api.binance.com/api/v3/ticker/price?symbols=[${pairs}]`,
  ) as Array<{ symbol: string; price: string }> | null;
  const out: Record<string, number> = {};
  for (const row of data ?? []) {
    const base = row.symbol.replace(/USDT$/, "");
    const price = Number(row.price);
    if (Number.isFinite(price) && price > 0) out[`${base}/USD`] = price;
  }
  return out;
}

/// Daily reference rates, used ONLY as a fallback for the quote->USD
/// conversion of currencies that have no live USD pair of their own.
async function referenceRates(): Promise<Record<string, number>> {
  const data = await fetchJson("https://open.er-api.com/v6/latest/USD") as
    { rates?: Record<string, number> } | null;
  return data?.rates ?? {};
}

/// USD per 1 unit of `code`: prefer the live mids just fetched.
function usdPerCurrency(code: string, mids: Record<string, number>, perUsd: Record<string, number>): number {
  if (!code || code === "USD") return 1;
  if (mids[`${code}/USD`] > 0) return mids[`${code}/USD`];
  if (mids[`USD/${code}`] > 0) return 1 / mids[`USD/${code}`];
  const r = perUsd[code];
  return r && r > 0 ? 1 / r : 1;
}

/// Mid -> client bid/ask with markup x global multiplier.
function toQuote(inst: Instrument, mid: number, rate: number, multiplier: number): Quote | null {
  if (!Number.isFinite(mid) || mid <= 0) return null;
  const point = Math.pow(10, -inst.digits);
  const points = Math.max(0, Math.round(inst.spread_markup_points * multiplier));
  const half = (points * point) / 2;
  const bid = Math.max(point, mid - half);
  const ask = bid + points * point;
  const dp = Math.max(inst.digits + 2, 8);
  return { bid: bid.toFixed(dp), ask: ask.toFixed(dp), rate: rate.toFixed(10) };
}

/// Run `fn` over `items` with at most `limit` in flight.
async function pool<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  });
  await Promise.all(workers);
  return out;
}

serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ success: false, message: "Function is not configured." }, 500);
  }

  // Optional shared secret so only the scheduler can trigger a sweep.
  const sweepSecret = Deno.env.get("SWEEP_SECRET");
  if (sweepSecret && req.headers.get("x-sweep-secret") !== sweepSecret) {
    return json({ success: false, message: "Forbidden." }, 403);
  }

  // Scheduled invocations may pass ?publish=false to sweep on existing quotes.
  const url = new URL(req.url);
  const doPublish = url.searchParams.get("publish") !== "false";
  // ?scope=metals: fast path for the 10-second schedule — spot metals
  // (gold-api.com) and crypto (one Binance call), no Yahoo calls. The full run
  // (forex, energy, indices, stocks) stays every minute.
  const metalsOnly = url.searchParams.get("scope") === "metals";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const [{ data: instruments, error: instErr }, { data: cfg }] = await Promise.all([
    admin
      .from("instruments")
      .select("symbol, category, base_currency, quote_currency, digits, spread_markup_points, trading_enabled")
      .eq("trading_enabled", true),
    admin.from("broker_config").select("spread_multiplier").eq("id", 1).maybeSingle(),
  ]);

  if (instErr) return json({ success: false, stage: "instruments", message: instErr.message }, 500);

  const multiplier = Math.min(10, Math.max(1, Number((cfg as { spread_multiplier?: number } | null)?.spread_multiplier ?? 1)));
  const list = ((instruments ?? []) as Instrument[])
    .filter((i) => !metalsOnly || SPOT_METAL[i.symbol] || i.category === "crypto");
  const quotes: Record<string, Quote> = {};
  const skipped: string[] = [];

  if (doPublish) {
    const nowS = Math.floor(Date.now() / 1000);
    const mids: Record<string, number> = {};

    const metals = await spotMetalMids(list.filter((i) => SPOT_METAL[i.symbol]).map((i) => i.symbol), nowS);
    Object.assign(mids, metals);

    const crypto = await binanceMids(list.filter((i) => i.category === "crypto").map((i) => i.symbol));
    Object.assign(mids, crypto);

    if (!metalsOnly) {
      const yahooTargets = list.filter((i) =>
        i.category !== "crypto" && !SPOT_METAL[i.symbol] && yahooSymbolFor(i));
      const yahooResults = await pool(yahooTargets, YAHOO_CONCURRENCY, async (i) =>
        [i.symbol, await yahooMid(yahooSymbolFor(i)!, nowS)] as const);
      for (const [sym, mid] of yahooResults) if (mid !== null) mids[sym] = mid;
    }

    // Metals and crypto are quoted in USD (rate 1), so the fast path needs no reference rates.
    const perUsd = metalsOnly ? {} : await referenceRates();

    for (const inst of list) {
      const mid = mids[inst.symbol];
      if (mid === undefined) {
        skipped.push(inst.symbol);
        continue;
      }
      const rate = usdPerCurrency(inst.quote_currency, mids, perUsd);
      const quote = toQuote(inst, mid, rate, multiplier);
      if (quote) quotes[inst.symbol] = quote;
    }
  }

  let published = 0;
  if (Object.keys(quotes).length > 0) {
    const { data, error } = await admin.rpc("rpc_publish_quotes", { p_quotes: quotes });
    if (error) return json({ success: false, stage: "publish", message: error.message }, 500);
    published = (data as { published?: number } | null)?.published ?? 0;
  }

  // Authoritative risk pass. The engine only EXECUTES on fresh publisher
  // quotes, so instruments skipped above are left untouched until they reopen.
  const { data: sweep, error: sweepErr } = await admin.rpc("rpc_sweep_accounts", { p_max_accounts: 500 });
  if (sweepErr) return json({ success: false, stage: "sweep", published, message: sweepErr.message }, 500);

  return json({
    success: true,
    instruments: list.length,
    quotes_built: Object.keys(quotes).length,
    published,
    spread_multiplier: multiplier,
    stale_or_closed: skipped,
    sweep,
  });
});
