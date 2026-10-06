# Security changes

## Automatic USDT deposit verification (2026-10-06)

Migration: `supabase/migrations/20261006000100_auto_verify_deposits.sql`
(SQL Editor copy: `APPLY_AUTO_VERIFY.sql`).
Edge Function: `supabase/functions/auto-verify-deposits/`.

### 1. Architecture

```
user enters amount ──► rpc_create_deposit_request
                         │  fx_assign_deposit_address()  (weighted rotation, row-locked)
                         ▼
                deposit_requests.address_used  ◄── shown to the user; client cannot choose it
                         │
     ┌───────────────────┴────────────────────┐
 auto_verify = false (Address A)          auto_verify = true (Address B)
 verification_status = NOT_REQUIRED       verification_status = WAITING
 user pays, attaches screenshot           user pays; nothing else to submit
 (rpc_attach_deposit_proof)                       │
         │                               auto-verify-deposits (every minute)
         ▼                                 TronGrid: list transfers to address_used,
 admin Pending ─► rpc_review_deposit        re-check each on /walletsolidity
                                                  │
                         ┌────────────────────────┼───────────────────────────┐
                    verified, ≤ limit        above limit                 30 min / 30 attempts
               rpc_system_approve_deposit   FAILED ABOVE_AUTO_LIMIT      FAILED TIMEOUT
               credits ON-CHAIN amount,           └────────► admin Pending ◄──┘
               ledger 'deposit:<id>',
               APPROVED / VERIFIED /
               approved_by_system = true
               ─► Auto-approved tab only
```

Every deposit stays in `deposit_requests` (audit, accounting, reconciliation).
Only deposits that need a human appear in **Pending**.

### 2. Address rotation (3:1)

- `company_deposit_addresses.weight` drives a weighted round-robin ordered by
  `sort_order`. With A=3, B=1 the sequence is **A, A, A, B, A, A, A, B, …**
- `deposit_rotation_state` holds one counter row, locked `FOR UPDATE` inside
  `fx_assign_deposit_address()`, so concurrent requests take consecutive,
  distinct slots.
- The address is assigned when the user asks for it (before paying) and stored
  in `deposit_requests.address_used`. A user with an open request (unpaid manual,
  or still verifying) gets that same request back, so the rotation is not burned.
- `rpc_submit_deposit_request` (one-shot claim used by older app builds, filed
  after the user already paid `broker_config.deposit_address_trc20`) is not
  rotated: rotating there could record a different address from the one paid.
  Those claims remain manual.

### 3. Addresses

| | Address | auto_verify | max_auto_approve_usd | weight |
|---|---|---|---|---|
| A | `TA199GDmT2ybpMKdHwZkjMgo2awuk1N1fV` | false (manual) | 1000 | 3 |
| B | `TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS` | true (automatic) | 1000 | 1 |

> **Warning:** Address A as given **fails TRON's Base58Check checksum**
> (TronGrid `/wallet/validateaddress` returns "Invalid address"). Wallets refuse
> to send to it. Replace it with the correct address (copied from the wallet)
> in Admin › Finance Desk › USDT Deposits › Deposit Addresses before going live.
> The admin screen now checks the checksum when adding an address and flags
> existing invalid ones.

### 4. TronGrid (no Tatum)

- Base URL `https://api.trongrid.io`. Tatum is not used anywhere.
- Discovery: `GET /v1/accounts/{address}/transactions/trc20?only_to=true&only_confirmed=true&contract_address=TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`.
  Users do not submit a TXID, so the function finds incoming transfers itself.
- Verification of every candidate on the irreversible (solidity) endpoints:
  `POST /walletsolidity/gettransactionbyid` and
  `POST /walletsolidity/gettransactioninfobyid`. All must hold:
  `ret[0].contractRet == SUCCESS` and receipt not failed; `TriggerSmartContract`;
  contract `41a614f803b6fd780986a42c78ec9c7f77e6ded13c` (USDT); data starts with
  `a9059cbb`; decoded recipient == `deposit_requests.address_used`; amount > 0
  (6 decimals). Sender, amount, block and result all come from the chain.
- Matching (no TXID): exact amount (to the cent) pairs oldest request with oldest
  transfer after it; a different amount is accepted only when there is exactly
  one waiting request and one unmatched transfer (on-chain amount credited).
  Anything ambiguous times out into manual review. A TXID can settle only one
  deposit (unique index on `lower(txid)`).
- Optional secret `TRONGRID_API_KEY`, sent as header `TRON-PRO-API-KEY`. Works
  without it at TronGrid's lower rate limit.
- HTTP 429: the run stops immediately; the next minute retries. Temporary
  network/API errors record an attempt and keep the deposit WAITING.
- No secret (`TRONGRID_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, tokens) is logged.

### 5. Security of the system RPCs

- `rpc_system_approve_deposit` and `rpc_system_mark_verification` check
  `fx_is_backend()` and are `REVOKE`d from `PUBLIC`, `anon` and `authenticated`;
  only `service_role` may execute them. The Edge Function uses
  `SUPABASE_SERVICE_ROLE_KEY` internally; it is never sent to the app.
- Approval locks the request `FOR UPDATE`, requires `PENDING` + `WAITING`
  (anything else returns `already_processed`), re-checks the recipient against
  `address_used`, enforces `max_auto_approve_usd`, credits the on-chain amount via
  `fx_lock_wallet`, and writes the ledger with idempotency key `deposit:<id>`
  (the same key the manual `rpc_review_deposit` uses) — one deposit, one credit.
- `rpc_review_deposit` refuses a deposit that is still `WAITING`
  (`AUTO_VERIFY_IN_PROGRESS`), so an admin and the system never both settle it.

### 6. Deploy and schedule

1. SQL Editor: run `APPLY_AUTO_VERIFY.sql`.
2. Edge Functions → Deploy new function `auto-verify-deposits`: paste
   `index.ts` and add a second file `tron.ts` (same folder). With the CLI:
   `supabase functions deploy auto-verify-deposits`.
3. Secrets: `SWEEP_SECRET` (already set for fx-price-sweep) and, optionally,
   `TRONGRID_API_KEY`.
4. SQL Editor: run `SCHEDULE_AUTO_VERIFY.sql` (git-ignored; pg_cron job
   `auto-verify-deposits`, every minute `* * * * *`, via pg_net with the
   `x-sweep-secret` header).

### 7. Configuration

**Address A = the admin's company deposit wallet** (migration
`20261006000200_admin_address_a.sql`). Admin › Finance Desk › USDT Deposits ›
*Company Deposit Wallet – Address A* → Save calls `rpc_admin_set_deposit_address`,
which (under the rotation lock, audited):
- makes the saved address the manual Address A: weight 3, first in order;
- deactivates the previous Address A (row kept for history);
- leaves the automatic Address B untouched (every 4th request);
- refuses Address B itself (`ADDRESS_IS_AUTOMATIC`);
- mirrors the address into `broker_config.deposit_address_trc20`.
The app also rejects addresses whose Base58Check checksum fails.

Advanced rotation settings (same screen, collapsed) — **Deposit Addresses**:
- **Auto Verify** switch per address (on = automatic, off = manual).
- **Max Auto Approve $** per address; above it a deposit goes to Pending as
  `ABOVE_AUTO_LIMIT` and is not credited automatically.
- **Weight** (rotation share) and **Active**. Keep A=3, B=1 for the 3:1 pattern.

Equivalent SQL:
```sql
SELECT public.rpc_admin_upsert_deposit_address('TNK1ngQW59zsu5iHntaGKiuUJ9PmSYJYtS',
       p_auto_verify => true, p_max_auto_approve_usd => 1000);
```

### 8. Tests

- `supabase/functions/auto-verify-deposits/tron_test.ts` — Base58/hex, transfer
  decoding, all verification checks, matching
  (`node --experimental-strip-types …/tron_test.ts`).
- `supabase/tests/auto_verify_test.sql` — rotation A,A,A,B x3, address_used,
  WAITING/NOT_REQUIRED, permissions, on-chain credit once, idempotency,
  recipient check, limit, timeout, admin queues (local/staging DB only).
- `test/auto_verify_deposits_test.dart` — app service, admin Pending /
  Auto-approved, address manager, user deposit states.
