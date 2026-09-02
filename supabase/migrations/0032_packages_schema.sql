-- Phase 2: Packages / Membership -- catalog + entitlement schema.
--
-- Two different write-control classes, matching this codebase's own
-- established split:
--   - packages/package_items: a catalog definition, same class as
--     services/products (0006/0015) -- SELECT for any member, direct
--     INSERT/UPDATE/DELETE at MANAGER+ via RLS, no RPC needed.
--   - customer_packages/customer_package_items/customer_package_redemptions:
--     financial/entitlement records, same class as appointments (0030) --
--     SELECT-only RLS, all writes through purchase_package/
--     set_appointment_status/void_sale (0036/0037).
--
-- Purchased packages are immutable snapshots (name_snapshot,
-- price_paid_snapshot, per-item name_snapshot/total_sessions) so editing or
-- deleting a package definition never retroactively changes what a
-- customer already owns -- package_id/service_id links on the customer-
-- facing tables are therefore nullable and `on delete set null`.
--
-- customer_package_redemptions is an append-only ledger (mirrors
-- inventory_movements' role): reversal is the `reversed` flag, never a
-- physical delete. The partial unique index on appointment_item_id is the
-- DB-level duplicate-redemption guard, not just an application check.

create type customer_package_status as enum ('ACTIVE', 'EXPIRED', 'CANCELLED');

create table packages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  description text,
  price numeric(14,2) not null check (price >= 0),
  validity_days integer check (validity_days is null or validity_days > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index packages_business_id_idx on packages(business_id);

create trigger packages_set_updated_at
  before update on packages
  for each row execute function set_updated_at();

create table package_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  package_id uuid not null references packages(id) on delete cascade,
  service_id uuid not null references services(id) on delete restrict,
  session_count integer not null check (session_count > 0),
  created_at timestamptz not null default now()
);

create index package_items_package_id_idx on package_items(package_id);
create index package_items_business_id_idx on package_items(business_id);
create index package_items_service_id_idx on package_items(service_id);

create table customer_packages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  package_id uuid references packages(id) on delete set null,
  sale_id uuid references sales(id) on delete set null,
  name_snapshot text not null,
  price_paid_snapshot numeric(14,2) not null check (price_paid_snapshot >= 0),
  purchased_at timestamptz not null default now(),
  expires_at timestamptz,
  status customer_package_status not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index customer_packages_business_id_idx on customer_packages(business_id);
create index customer_packages_customer_id_idx on customer_packages(customer_id);
create index customer_packages_sale_id_idx on customer_packages(sale_id);
create index customer_packages_status_idx on customer_packages(business_id, status);

create trigger customer_packages_set_updated_at
  before update on customer_packages
  for each row execute function set_updated_at();

create table customer_package_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_package_id uuid not null references customer_packages(id) on delete cascade,
  service_id uuid references services(id) on delete set null,
  name_snapshot text not null,
  total_sessions integer not null check (total_sessions > 0),
  used_sessions integer not null default 0 check (used_sessions >= 0 and used_sessions <= total_sessions),
  created_at timestamptz not null default now()
);

create index customer_package_items_customer_package_id_idx on customer_package_items(customer_package_id);
create index customer_package_items_business_id_idx on customer_package_items(business_id);
create index customer_package_items_service_id_idx on customer_package_items(service_id);

create table customer_package_redemptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_package_item_id uuid not null references customer_package_items(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete set null,
  appointment_item_id uuid references appointment_items(id) on delete set null,
  staff_id uuid references profiles(id) on delete set null,
  redeemed_at timestamptz not null default now(),
  reversed boolean not null default false
);

create index customer_package_redemptions_business_id_idx on customer_package_redemptions(business_id);
create index customer_package_redemptions_item_idx on customer_package_redemptions(customer_package_item_id);

-- Duplicate-redemption guard: at most one non-reversed redemption per
-- appointment_item. NULL appointment_item_id rows (none expected via the
-- approved RPC, but not structurally impossible) are simply not covered by
-- this partial index, same as any other partial-unique-index NULL handling.
create unique index customer_package_redemptions_appointment_item_unique
  on customer_package_redemptions(appointment_item_id)
  where not reversed and appointment_item_id is not null;

alter table packages enable row level security;
alter table package_items enable row level security;
alter table customer_packages enable row level security;
alter table customer_package_items enable row level security;
alter table customer_package_redemptions enable row level security;

-- packages / package_items: catalog pattern (mirrors services/products).

create policy packages_select on packages
  for select using (is_member(business_id));

create policy packages_insert on packages
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy packages_update on packages
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy packages_delete on packages
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy package_items_select on package_items
  for select using (is_member(business_id));

create policy package_items_insert on package_items
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy package_items_update on package_items
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy package_items_delete on package_items
  for delete using (has_role_at_least(business_id, 'MANAGER'));

-- customer_packages / customer_package_items / customer_package_redemptions:
-- financial/entitlement pattern (mirrors appointments) -- SELECT only, all
-- writes through purchase_package/set_appointment_status/void_sale.

create policy customer_packages_select on customer_packages
  for select using (is_member(business_id));

create policy customer_package_items_select on customer_package_items
  for select using (is_member(business_id));

create policy customer_package_redemptions_select on customer_package_redemptions
  for select using (is_member(business_id));
