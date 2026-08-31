# Beauty Clinic POS — Implementation Plan

Status snapshot: **Day 5 complete; Day 6 (Security + Hardening) in
progress** — Day 1 (Foundation), Day 2 (POS Core), Day 3 (CRM + Staff +
Commission), Day 4 (Inventory + Expenses), and Day 5 (Dashboard +
Reports) are implemented and verified green against the live Supabase
project. Day 6's RLS/RPC privilege audit and hardening pass is complete
and verified live; its refund/void flow, full audit-log wiring, and UX
polish items remain pending. This document is updated as each day
lands — it reflects what's actually built, not aspirations. See the
Definition of Done checklist at the bottom for live status.

## 1. Product & Stack

Beauty Clinic / Spa / Salon POS. Flutter (Material 3, web/desktop-first,
tablet/mobile usable) + Supabase (Postgres, Auth, Storage, Realtime, RLS).
No separate backend server — Postgres is the source of truth for every
business-critical calculation and constraint.

## 2. Architecture

Feature-first Flutter structure:

```
lib/
  app/            # MaterialApp.router, GoRouter config
  config/         # env.dart (compile-time config), supabase_config.dart
  theme/          # design system: colors, typography, spacing, ThemeData
  core/           # shared widgets, error translation, utils
  shared/         # models and providers used across features
  features/
    auth/         # sign in/up, password reset, business onboarding
    dashboard/    # authenticated shell (sidebar nav + content area)
    pos/          # checkout flow (Day 2)
    customers/    # CRM (Day 3)
    services/     # service catalog (Day 2)
    products/     # product catalog (Day 2)
    inventory/    # stock movements (Day 4)
    staff/        # business_members management (Day 3)
    commissions/  # commission ledger + reports (Day 3)
    expenses/     # expense tracking (Day 4)
    reports/      # dashboard + reports (Day 5)
    settings/     # business settings (Day 6)
supabase/
  migrations/     # numbered SQL migrations — the schema source of truth
  bootstrap_all.sql  # generated concatenation for one-shot SQL Editor apply
```

State management: Riverpod (providers colocated with each feature's
`presentation/` layer). Routing: go_router, with a redirect gate on auth
state and a `HomeGate` widget that branches to onboarding vs. the
dashboard shell based on the user's business memberships.

## 3. Multi-Tenant Data Model

Every business-owned table carries `business_id`, and no table trusts a
client-supplied `business_id` beyond what RLS re-derives server-side from
`business_members` for `auth.uid()`.

Tables (see `supabase/migrations/0001`–`0013`):
`businesses`, `branches`, `profiles`, `business_members`, `customers`,
`customer_notes`, `service_categories`, `services`, `product_categories`,
`products`, `suppliers`, `sales`, `sale_items`, `payments`,
`inventory_movements`, `commissions`, `expense_categories`, `expenses`,
`settings`, `audit_logs`.

Key design choices:
- **Money**: `numeric(14,2)` in Postgres; the `decimal` package in Dart —
  never `double` for monetary math.
- **Snapshots**: `sale_items.name_snapshot` and `unit_price` are captured
  at sale time so a later price change never rewrites history.
- **Append-only ledgers**: `inventory_movements`, `sale_items`,
  `audit_logs` have no UPDATE/DELETE RLS policy at all — corrections are
  new rows, not edits.
- **No hard delete on sales**: `sales` has no DELETE policy; void/refund
  is a status UPDATE gated to MANAGER+.
- **Idempotency**: `sales.idempotency_key` is unique per business — the
  Day 2 checkout RPC will use this to make double-submits a no-op instead
  of a duplicate sale.

## 4. Roles & RLS Strategy

`business_role` enum: `OWNER > ADMIN > MANAGER > CASHIER > STAFF` (rank
5→1). `business_members` is the single source of truth for "who can do
what in which business."

Helper functions (`0014_rls_helpers.sql`), all `SECURITY DEFINER` with a
pinned `search_path` so they can read `business_members` without
recursing through its own RLS:
- `is_member(business_id)` — active membership exists for `auth.uid()`.
- `member_role(business_id)` — caller's role, or null.
- `has_role_at_least(business_id, min_role)` — rank comparison.

Every business table: `alter table ... enable row level security;` plus
SELECT gated to `is_member`, and INSERT/UPDATE/DELETE gated to the
minimum role from the permission matrix below. `business_members` itself
has extra guards so a plain ADMIN cannot self-escalate to OWNER/ADMIN or
touch an existing OWNER's row (`0015_rls_policies.sql`), and a trigger
(`guard_last_owner`, `0016`) blocks removing/demoting a business's last
OWNER.

### Permission matrix (write floor by table group)

| Area | OWNER | ADMIN | MANAGER | CASHIER | STAFF |
|---|---|---|---|---|---|
| Business settings, branches | ✓ | ✓ | | | |
| Staff / roles | ✓ | ✓ | | | |
| Products, services, inventory | ✓ | ✓ | ✓ | | |
| Customers, sales, payments | ✓ | ✓ | ✓ | ✓ | |
| Expenses | ✓ | ✓ | | | |
| Commissions (correction) | ✓ | ✓ | | | |
| Audit log (read) | ✓ | ✓ | | | |
| POS / own assigned sales | ✓ | ✓ | ✓ | ✓ | read-only |

**Follow-up privilege correction (Day 3):** `find_invitable_user_id`
(added in `0018_staff_invite_lookup.sql`) needed a second migration,
`0019_revoke_anon_execute_on_staff_invite_lookup.sql`, because this
project's default privileges grant `EXECUTE` on every newly created
`public` function to `anon` as a separate ACL entry — independent of, and
not touched by, `revoke ... from public`. `0019` revokes `anon` execute on
this one function specifically. A broader, project-wide default-privilege
sweep (i.e. an `ALTER DEFAULT PRIVILEGES` change affecting every future
function) remains intentionally out of scope and undone — but Day 6's
security audit confirmed the same gap on `create_business_with_owner`,
`invite_business_member`, and `complete_sale` and closed it the same
per-function way in `0021_revoke_anon_execute_on_onboarding_and_checkout.sql`,
so all five sensitive functions in this project
(`find_invitable_user_id`, `adjust_stock`, `create_business_with_owner`,
`invite_business_member`, `complete_sale`) are now individually hardened.

## 5. Transaction / RPC Strategy

Business-critical multi-step writes go through `SECURITY DEFINER`
Postgres functions (RPC), not client-orchestrated multi-table writes,
so they're atomic and can't be left half-done by a dropped connection:

- **`create_business_with_owner`** (done) — business + OWNER membership +
  default branch, atomically. There is deliberately no client-facing
  INSERT policy on `businesses`.
- **`invite_business_member`** (done) — add/reactivate a member with
  role-escalation rules enforced once, matching the RLS guards.
- **`complete_sale`** (Day 2) — sale + sale_items + payment + inventory
  decrement + commission rows + customer stats update + audit log, in one
  transaction, keyed by `idempotency_key` so a retried submit is a no-op.
- **`void_sale`** (Day 6) — status update + inventory reversal +
  commission reversal + audit log.

Edge Functions are reserved for logic that must not run as the
authenticated user at all (e.g. future external integrations); everything
above is plain Postgres RPC, per the "don't build an Edge Function for
every CRUD op" guidance.

## 6. Testing Strategy

- `flutter analyze` / `flutter test` on every change (unit tests for pure
  logic like `BusinessRole`, widget tests for screens).
- RLS is tested by exercising it as real authenticated users, not just
  read — the acceptance test in section 59 of the spec (cross-business
  access must be denied) is the bar.
- No mocked completion: a feature isn't reported done until it's wired to
  the real Supabase project and exercised end-to-end.

## 7. 7-Day Timeline

1. **Foundation** (done) — Flutter scaffold, design system, full
   schema + RLS migrations, auth, business onboarding, dashboard shell.
2. **POS Core** (done) — services/products CRUD, cart, checkout RPC, payments,
   receipt.
3. **CRM + Staff** (done) — customer profiles/history, staff management,
   commission calculation.
4. **Inventory + Expenses** (done) — stock movements wired to sales,
   suppliers, low-stock, expense tracking.
5. **Dashboard + Reports** (done) — real metrics (today's sales, commission,
   expenses, estimated profit), report filters/export.
6. **Security + Hardening** (in progress — RLS/RPC privilege audit and
   hardening done and verified live; refund/void flow, audit log wiring
   across all mutations, and UX polish still pending) — refund/void flow,
   audit log wiring across all mutations, RLS re-audit, error handling
   pass, UX polish.
7. **QA + Deployment** — full test matrix (section 46/47 of the spec),
   production build, deployment, documentation.

## 8. Deployment

Flutter Web build (`flutter build web`) as the primary target, deployable
to any static host; Windows desktop build as a secondary target for
in-clinic kiosk use. Supabase project is the only backend — no servers to
deploy. Secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) are injected via
`--dart-define-from-file=env.json`, which is gitignored
(`env.example.json` is the committed template). The Supabase service role
key is never used by this client and never enters the repository.

## 9. Applying the database schema

The schema exists only as migrations under `supabase/migrations/` — there
is no live database until they're applied. Two ways to apply them to a
fresh Supabase project:

- **SQL Editor (no extra credentials needed):** paste
  `supabase/bootstrap_all.sql` into the Supabase Dashboard's SQL Editor
  and run it once. It's wrapped in `begin;`/`commit;` so it applies
  atomically.
- **Supabase CLI:** `supabase link` + `supabase db push`, if you'd rather
  automate it (needs your DB password or an access token, which this
  session does not have).

## 10. Definition of Done

- [x] Supabase connected (Flutter client wired; schema applied — see
      section 9)
- [x] Database migrations complete (Day 1 core schema)
- [x] RLS enabled on every business table
- [x] Authentication works (sign up, sign in, password reset, sign out)
- [x] Roles work (`business_role` + RLS permission matrix)
- [x] Customer CRM
- [x] Services
- [x] Products
- [x] POS
- [x] Payments
- [x] Receipts
- [x] Inventory
- [x] Commission
- [x] Expenses
- [x] Dashboard (real metrics)
- [x] Reports
- [x] Refund/Void (`void_sale` RPC, `0026_void_sale.sql` — F9-2, verified
      live)
- [x] Audit logs wired to every mutation (extended beyond `complete_sale`
      to `adjust_stock`, `set_member_role`, `set_member_active`
      (`0027_audit_log_coverage.sql`, F9-3) and `update_business_settings`
      (`0028_business_settings_rpc.sql`, F9-4))
- [x] Duplicate transaction protection (`sales.idempotency_key`, enforced
      by `complete_sale` — verified live: a retried submit is a no-op,
      not a duplicate sale)
- [x] Error handling (friendly error translation layer; expands as
      features land)
- [x] Responsive UI (sidebar shell + POS-specific responsive layout)
- [x] Security tests (live authorization regression coverage across POS,
      CRM, staff, and commissions — see Day 3 completion notes below)
- [x] RLS tests (cross-tenant isolation, OWNER/escalation guards, and
      append-only policies all exercised as real authenticated users)
- [x] `flutter analyze` passes
- [x] `flutter test` passes
- [x] production build verified (`flutter build web
      --dart-define-from-file=env.json` — exit 0)
- [ ] deployment (target not yet chosen — see §8)
- [ ] documentation complete (production build + env config documented in
      README; deployment procedure blocked on target decision)

**Day 3 completion notes** (2026-08-28 live verification):
- Customer CRM (list/search, create/edit, profile) — done.
- Customer purchase history (via `sales`) — done.
- Customer notes (append-only, no update/delete policy) — done.
- Staff roster, roles, activate/deactivate — done.
- Staff invite-by-email (`find_invitable_user_id` → `invite_business_member`) — done.
- Commission calculation (via `complete_sale`) and commission ledger
  (list/filter/status transitions) — done.
- Dashboard navigation wired for Customers, Staff, and Commissions — done.
- Live regression gates, all green against the live Supabase project:
  - Day 2 POS regression: 4/4
  - Day 3 Customer/Staff/Commission regression: 8/8
  - Staff invite lookup regression: 7/7
  - F1 + SEC-CRITICAL regression: 6/6
  - `flutter analyze`: no issues
  - `flutter test` (full suite): all passing (live suites skip without
    `env.json` credentials)

**Day 4 completion notes** (2026-08-28 live verification):
- Inventory stock adjustment RPC (`adjust_stock`, added in
  `0020_inventory_stock_adjustment.sql`) — atomically inserts the
  `inventory_movements` row and updates `products.stock_quantity` in one
  transaction, so a client never has to orchestrate the two writes itself.
  MANAGER+ only, product row locked and re-verified against
  `business_id`, negative stock rejected, and `SALE` is blocked as a
  manual movement type (that stays `complete_sale`-only) — done.
- Supplier management (list/create/edit) — done.
- Inventory movement ledger (read view over `inventory_movements`,
  including manual adjustments and existing sale-driven movements) —
  done.
- Low-stock surfacing in the Stock tab, reusing the existing
  `Product.isLowStock` getter from Day 2 — done.
- Expense categories and expenses (list/filter, create/edit/delete) —
  done.
- RLS/cross-tenant isolation: no new RLS policy was needed — suppliers,
  inventory_movements, expense_categories, and expenses have carried
  their RLS since the Day 1 foundation migrations; Day 4 only added the
  one RPC required for atomic stock adjustment. Cross-tenant reads and
  under-privileged writes were verified live to fail exactly like every
  other Day 2/3 table.
- Live regression gates, all green against the live Supabase project
  (migration `0020` applied and verified):
  - Day 4 Inventory/Expenses regression: 9/9
  - Day 2 POS regression (frozen): 4/4
  - F1 + SEC-CRITICAL regression (frozen): 6/6
  - Day 3 Customer/Staff/Commission regression (frozen): 8/8
  - Staff invite lookup regression (frozen): 7/7
  - `flutter analyze`: no issues
  - `flutter test` (full suite): 17 passed, 35 skipped, 0 failed (live
    suites skip without `env.json` credentials)

**Day 5 completion notes** (2026-08-29 live verification):
- Real metrics on the Overview tab (today's revenue, commission, expenses,
  estimated profit) — done. Overview's visibility is intentionally left
  unchanged (all roles, matching every other Day 1–4 day) — the read RLS
  on `sales`/`commissions`/`expenses` already permits any active member to
  read these rows, so restricting the tab would be cosmetic, not a real
  security boundary; `Reports` keeps its existing `MANAGER`+ gate.
- Reports screen (existing stub nav item) with a Today / This week / This
  month / Custom date-range filter, the same four metrics for the
  selected range, a daily-revenue chart (`fl_chart`, already a
  dependency), a sales table (`data_table_2`, already a dependency), and
  a dependency-free CSV export (built client-side, copied to the
  clipboard via `package:flutter/services.dart`) — done.
- No migration, no new RLS policy, and no new RPC were needed — every
  query is a plain read against `sales`, `sale_items`, `commissions`,
  `expenses`, and `products`, all of which have carried
  `is_member(business_id)` SELECT RLS since the Day 1 foundation
  migrations. Day 5 introduces no new write path at all.
- Estimated profit = revenue − COGS − commissions − expenses, where COGS
  is each `PRODUCT` sale item's quantity × the product's *current*
  `cost_price` (no historical cost is snapshotted anywhere in the schema,
  hence "estimated" — `cost_price` existed on `Product` since Day 2 but
  had no consumer until now).
- Live-verification bug found and fixed during this day's own testing
  (not a regression in any frozen day): `ReportsRepository`'s date-range
  filters against `timestamptz` columns (`sales`/`sale_items`/
  `commissions.created_at`) initially compared against naive local-time
  ISO strings, which Postgres silently interprets as UTC — an hours-wide
  skew for this project's non-UTC deployment. Fixed by converting to UTC
  before filtering (`_instant()` in `reports_repository.dart`);
  `expenses.expense_date` (a plain `date` column, no time-of-day
  component) was unaffected and needed no change.
- Live regression gates, all green against the live Supabase project:
  - Day 5 Reports regression: 4/4
  - Day 2 POS regression (frozen): 4/4
  - F1 + SEC-CRITICAL regression (frozen): 6/6
  - Day 3 Customer/Staff/Commission regression (frozen): 8/8
  - Staff invite lookup regression (frozen): 7/7
  - Day 4 Inventory/Expenses regression (frozen): 9/9
  - `flutter analyze`: no issues
  - `flutter test` (full suite): 17 passed, 39 skipped, 0 failed (live
    suites skip without `env.json` credentials)
- Known deferred work: export is clipboard-CSV only (no file-download or
  share-sheet package was added, per "no new dependencies unless
  absolutely required"); no report result is cached, so switching the
  date-range filter re-queries live each time.

**Day 6 completion notes** (2026-08-30 live verification — RLS/RPC
privilege audit and hardening pass; refund/void flow, full audit-log
wiring, and UX polish remain pending for the rest of Day 6):
- A forensic security audit of Days 1–5's RLS policies, RPCs, and
  privilege grants found four findings, all fixed and verified live:
  - **F1 (financial/snapshot column protection)**: `sales_update`,
    `payments_update`, and `commissions_update` RLS correctly gated *who*
    could write (MANAGER+/ADMIN+) but not *which columns* — a privileged
    session against the raw REST API could have rewritten `total_amount`,
    `paid_amount`, `commission_amount`, staff attribution, or
    `idempotency_key` directly, bypassing every guarantee `complete_sale`
    established at creation. Fixed with `BEFORE UPDATE` triggers
    (`0022_protect_financial_snapshot_columns.sql`) that reject changes to
    server-computed/snapshot columns while still allowing `status`/void
    metadata to change. `complete_sale` only ever `INSERT`s into these
    tables, so the Day 2 checkout path is unaffected — confirmed live.
  - **F2 (customer lifetime metrics protection)**: `customers.total_spent`
    /`visit_count`/`last_visit_at` are running totals only `complete_sale`
    should maintain, but `customers_update` RLS (CASHIER+) had no column
    restriction. Since these three columns *do* need a legitimate internal
    writer, a blanket block would have broken checkout — fixed instead
    with a transaction-local trusted-context flag (`set_config('app.
    trusted_customer_stats_update', 'true', true)`, set by `complete_sale`
    immediately before its own update) that a new `customers` trigger
    checks (`0023_complete_sale_customer_integrity.sql`). A client cannot
    forge this context: `set_config` is a `pg_catalog` builtin never
    exposed as a PostgREST RPC, and the flag is scoped to `complete_sale`'s
    own transaction only. Verified live both ways: a direct API update to
    `total_spent` is rejected, and `complete_sale` still updates all three
    columns correctly for a real sale.
  - **F3 (RPC EXECUTE privilege hardening)**: live empirical probing
    (the same anonymous-RPC technique that discovered the Day 3
    `find_invitable_user_id` gap) proved `anon` still held live `EXECUTE`
    on `create_business_with_owner`, `invite_business_member`, and
    `complete_sale` — each was protected only by its own internal
    application check, with no ACL-level backstop, unlike
    `find_invitable_user_id`/`adjust_stock`. Fixed in
    `0021_revoke_anon_execute_on_onboarding_and_checkout.sql`: explicit
    `revoke ... from anon` for all three, plus an explicit
    `auth.uid() is null` guard added to `invite_business_member` for
    consistency (it previously relied on an implicit null-role rejection).
    Verified live: all five sensitive functions
    (`find_invitable_user_id`, `adjust_stock`, `create_business_with_owner`,
    `invite_business_member`, `complete_sale`) now return Postgres's own
    `42501 permission denied` to an anonymous caller.
  - **F4 (`complete_sale` customer tenant validation)**: `p_customer_id`
    was written into `sales.customer_id` with no check that it belonged to
    `p_business_id`, unlike `service_id`/`product_id`/`staff_id` in the
    same function, which are all re-validated. Fixed in
    `0023_complete_sale_customer_integrity.sql` with the same validation
    style already used for `staff_id`; a cross-tenant or nonexistent
    `customer_id` now raises `Customer not found in this business`, while
    `NULL` (walk-in sales) is unaffected.
- No RLS policy was weakened, no existing RPC's authorization was loosened,
  `guard_last_owner` and `BusinessRepository.myMemberships()` were not
  touched, and no `ALTER DEFAULT PRIVILEGES` was used anywhere.
- Test-process note, for transparency: the first version of the new Day 6
  test suite's F3 "legitimate call still works" check for
  `create_business_with_owner` called the real RPC with a real name,
  permanently creating an extra business — since `businesses` has no
  DELETE policy and `guard_last_owner` requires at least one active OWNER
  at all times, this could not be undone by deleting it. It was resolved
  entirely through legitimate, RLS-respecting application paths: a
  dedicated custodian account (created via the Supabase Dashboard, not
  self-service signup — this project's email validation rejects the
  `.local` fixture domain) was added as the orphan business's OWNER via
  the existing `invite_business_member` RPC, after which both real
  fixture accounts' memberships in that business were deactivated —
  restoring their `firstWhere(role == owner)` fixture resolution used
  throughout the suite. No direct SQL, no service-role credential, and no
  RLS bypass were used at any point. The test itself was then redesigned
  to call `create_business_with_owner` with a deliberately blank
  `p_name`, asserting the function's own `Business name is required`
  validation — proving the authenticated path still works past the new
  ACL with zero persistent side effects.
- Live regression gates, all green against the live Supabase project
  after the hardening migrations (`0021`–`0023`) were applied:
  - Day 6 Security Hardening regression: 10/10
  - Day 2 POS regression (frozen): 4/4
  - F1 + SEC-CRITICAL regression (frozen): 6/6
  - Day 3 Customer/Staff/Commission regression (frozen): 8/8
  - Staff invite lookup regression (frozen): 7/7
  - Day 4 Inventory/Expenses regression (frozen): 9/9
  - Day 5 Reports regression (frozen): 4/4
  - Combined Day 2–6 total: 35/35
  - `flutter analyze`: no issues
  - `flutter test` (full suite): 17 passed, 49 skipped, 0 failed (live
    suites skip without `env.json` credentials)
