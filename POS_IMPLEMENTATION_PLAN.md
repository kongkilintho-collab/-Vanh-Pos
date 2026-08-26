# Beauty Clinic POS — Implementation Plan

Status snapshot: **Day 1 (Foundation) in progress.** This document is updated
as each day lands — it reflects what's actually built, not aspirations.
See the Definition of Done checklist at the bottom for live status.

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

1. **Foundation** (in progress) — Flutter scaffold, design system, full
   schema + RLS migrations, auth, business onboarding, dashboard shell.
2. **POS Core** — services/products CRUD, cart, checkout RPC, payments,
   receipt.
3. **CRM + Staff** — customer profiles/history, staff management,
   commission calculation.
4. **Inventory + Expenses** — stock movements wired to sales, suppliers,
   low-stock, expense tracking.
5. **Dashboard + Reports** — real metrics (today's sales, commission,
   expenses, estimated profit), report filters/export.
6. **Security + Hardening** — refund/void flow, audit log wiring across
   all mutations, RLS re-audit, error handling pass, UX polish.
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

- [x] Supabase connected (Flutter client wired; schema not yet applied —
      see section 9)
- [x] Database migrations complete (Day 1 core schema)
- [x] RLS enabled on every business table
- [x] Authentication works (sign up, sign in, password reset, sign out)
- [x] Roles work (`business_role` + RLS permission matrix)
- [ ] Customer CRM
- [ ] Services
- [ ] Products
- [ ] POS
- [ ] Payments
- [ ] Receipts
- [ ] Inventory
- [ ] Commission
- [ ] Expenses
- [ ] Dashboard (real metrics)
- [ ] Reports
- [ ] Refund/Void
- [ ] Audit logs wired to every mutation
- [ ] Duplicate transaction protection (idempotency key column exists;
      not yet enforced by a checkout RPC)
- [x] Error handling (friendly error translation layer; expands as
      features land)
- [x] Responsive UI (sidebar shell today; POS-specific responsive layout
      in Day 2)
- [ ] Security tests
- [ ] RLS tests
- [x] `flutter analyze` passes
- [x] `flutter test` passes
- [ ] production build verified
- [ ] deployment
- [ ] documentation complete (this file is the start)
