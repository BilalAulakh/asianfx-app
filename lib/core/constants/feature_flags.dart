/// Compile-time feature switches.
library;

/// Two-factor authentication is NOT implemented (no Supabase MFA enrolment /
/// challenge / AAL2 enforcement). The old screens only waited on a timer and
/// accepted any 6 digits. Until real TOTP MFA ships, the UI says "coming soon"
/// instead of pretending to protect the account.
const bool kTwoFactorAvailable = false;

/// Demo pricing: synthetic micro-ticks and generated candle history so the
/// terminal looks alive without a market feed. NEVER enable for real money.
/// Build with `--dart-define=ASIANFX_DEMO_MODE=true` to turn it on; the app
/// then shows a permanent "DEMO PRICES" banner.
const bool kDemoMode = bool.fromEnvironment('ASIANFX_DEMO_MODE', defaultValue: false);
