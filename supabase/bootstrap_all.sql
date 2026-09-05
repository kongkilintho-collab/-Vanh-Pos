-- Generated convenience copy for pasting into the Supabase SQL Editor.
-- The individual files in supabase/migrations/ are the source of truth —
-- if you change the schema, edit those files and regenerate this one.
--
-- Wrapped in a transaction so a mistake partway through rolls back
-- cleanly instead of leaving a half-applied schema.
begin;

-- ===== 0001_extensions_and_enums.sql =====
-- Extensions
create extension if not exists pgcrypto;

-- Enums
create type business_role as enum ('OWNER', 'ADMIN', 'MANAGER', 'CASHIER', 'STAFF');
create type commission_kind as enum ('PERCENTAGE', 'FIXED');
create type sale_item_kind as enum ('SERVICE', 'PRODUCT');
create type sale_status as enum ('COMPLETED', 'VOIDED', 'REFUNDED');
create type payment_status_enum as enum ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED');
create type payment_method_enum as enum ('CASH', 'BANK_TRANSFER', 'CARD', 'OTHER');
create type inventory_movement_type as enum ('PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT', 'DAMAGE', 'EXPIRED');
create type commission_status as enum ('PENDING', 'APPROVED', 'REVERSED', 'PAID');
create type audit_action as enum (
  'LOGIN', 'LOGOUT', 'CREATE', 'UPDATE', 'DELETE', 'VOID', 'REFUND',
  'PAYMENT', 'STOCK_ADJUSTMENT', 'PERMISSION_CHANGE', 'SETTINGS_CHANGE'
);

-- Shared trigger: keep updated_at current on every row update.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ===== 0002_businesses_branches.sql =====
create table businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  logo_url text,
  phone text,
  email text,
  address text,
  currency text not null default 'LAK' check (char_length(currency) = 3),
  timezone text not null default 'Asia/Vientiane',
  tax_enabled boolean not null default false,
  tax_rate numeric(5,2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger businesses_set_updated_at
  before update on businesses
  for each row execute function set_updated_at();

create table branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index branches_business_id_idx on branches(business_id);

create trigger branches_set_updated_at
  before update on branches
  for each row execute function set_updated_at();

-- ===== 0003_profiles.sql =====
-- Mirrors auth.users 1:1. No passwords or auth secrets live here.
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) > 0),
  phone text,
  avatar_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute function set_updated_at();

-- Auto-create a profile row whenever a new auth user is created.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'phone'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- ===== 0004_business_members.sql =====
-- Membership + role of a user within a business. This is the multi-tenant
-- join table every RLS policy in the system keys off of.
create table business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role business_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create index business_members_business_id_idx on business_members(business_id);
create index business_members_user_id_idx on business_members(user_id);

create trigger business_members_set_updated_at
  before update on business_members
  for each row execute function set_updated_at();

-- ===== 0005_customers.sql =====
create table customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  gender text check (gender in ('MALE', 'FEMALE', 'OTHER')),
  birthday date,
  notes text,
  total_spent numeric(14,2) not null default 0,
  visit_count integer not null default 0,
  last_visit_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index customers_business_id_idx on customers(business_id);
create index customers_phone_idx on customers(business_id, phone);
create index customers_name_idx on customers using gin (to_tsvector('simple', name));

create trigger customers_set_updated_at
  before update on customers
  for each row execute function set_updated_at();

create table customer_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  note text not null check (char_length(trim(note)) > 0),
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index customer_notes_customer_id_idx on customer_notes(customer_id);

-- ===== 0006_catalog.sql =====
-- Services -----------------------------------------------------------------

create table service_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger service_categories_set_updated_at
  before update on service_categories
  for each row execute function set_updated_at();

create table services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  category_id uuid references service_categories(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  description text,
  price numeric(14,2) not null check (price >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  commission_type commission_kind not null default 'PERCENTAGE',
  commission_value numeric(14,2) not null default 0 check (commission_value >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index services_business_id_idx on services(business_id);
create index services_category_id_idx on services(category_id);

create trigger services_set_updated_at
  before update on services
  for each row execute function set_updated_at();

-- Products & suppliers -------------------------------------------------------

create table suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  email text,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger suppliers_set_updated_at
  before update on suppliers
  for each row execute function set_updated_at();

create table product_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger product_categories_set_updated_at
  before update on product_categories
  for each row execute function set_updated_at();

create table products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  category_id uuid references product_categories(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  sku text,
  barcode text,
  description text,
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  selling_price numeric(14,2) not null check (selling_price >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  minimum_stock integer not null default 0 check (minimum_stock >= 0),
  expiry_date date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, sku)
);

create index products_business_id_idx on products(business_id);
create index products_category_id_idx on products(category_id);
create index products_barcode_idx on products(business_id, barcode);
create index products_name_idx on products using gin (to_tsvector('simple', name));

create trigger products_set_updated_at
  before update on products
  for each row execute function set_updated_at();

-- ===== 0007_sales.sql =====
create sequence sales_receipt_seq;

create table sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  customer_id uuid references customers(id) on delete set null,
  cashier_id uuid not null references profiles(id) on delete restrict,
  receipt_number text not null default ('R-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(nextval('sales_receipt_seq')::text, 6, '0')),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null check (total_amount >= 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
  status sale_status not null default 'COMPLETED',
  payment_status payment_status_enum not null default 'PENDING',
  idempotency_key text,
  void_reason text,
  voided_by uuid references profiles(id) on delete set null,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, receipt_number),
  unique (business_id, idempotency_key)
);

create index sales_business_id_idx on sales(business_id);
create index sales_branch_id_idx on sales(branch_id);
create index sales_customer_id_idx on sales(customer_id);
create index sales_cashier_id_idx on sales(cashier_id);
create index sales_created_at_idx on sales(business_id, created_at);
create index sales_status_idx on sales(business_id, status);

create trigger sales_set_updated_at
  before update on sales
  for each row execute function set_updated_at();

create table sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  item_type sale_item_kind not null,
  service_id uuid references services(id) on delete set null,
  product_id uuid references products(id) on delete set null,
  staff_id uuid references profiles(id) on delete set null,
  name_snapshot text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  commission_amount numeric(14,2) not null default 0 check (commission_amount >= 0),
  created_at timestamptz not null default now(),
  constraint sale_items_item_reference_chk check (
    (item_type = 'SERVICE' and service_id is not null and product_id is null) or
    (item_type = 'PRODUCT' and product_id is not null and service_id is null)
  )
);

create index sale_items_sale_id_idx on sale_items(sale_id);
create index sale_items_business_id_idx on sale_items(business_id);
create index sale_items_staff_id_idx on sale_items(staff_id);
create index sale_items_service_id_idx on sale_items(service_id);
create index sale_items_product_id_idx on sale_items(product_id);

-- ===== 0008_payments.sql =====
create table payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  payment_method payment_method_enum not null,
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  status payment_status_enum not null default 'COMPLETED',
  created_by uuid not null references profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index payments_business_id_idx on payments(business_id);
create index payments_sale_id_idx on payments(sale_id);

-- ===== 0009_inventory.sql =====
-- Every stock change is traced here. Nothing should mutate
-- products.stock_quantity without a corresponding row in this table
-- (enforced in application/RPC logic, not by trigger, so adjustments can
-- carry context such as reference_type/reference_id).
create table inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  product_id uuid not null references products(id) on delete cascade,
  movement_type inventory_movement_type not null,
  quantity integer not null check (quantity <> 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index inventory_movements_business_id_idx on inventory_movements(business_id);
create index inventory_movements_product_id_idx on inventory_movements(product_id);
create index inventory_movements_reference_idx on inventory_movements(reference_type, reference_id);
create index inventory_movements_created_at_idx on inventory_movements(business_id, created_at);

-- ===== 0010_commissions.sql =====
create table commissions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  sale_item_id uuid not null references sale_items(id) on delete cascade,
  staff_id uuid not null references profiles(id) on delete restrict,
  commission_type commission_kind not null,
  commission_rate numeric(14,2) not null default 0 check (commission_rate >= 0),
  commission_amount numeric(14,2) not null check (commission_amount >= 0),
  status commission_status not null default 'PENDING',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sale_item_id)
);

create index commissions_business_id_idx on commissions(business_id);
create index commissions_staff_id_idx on commissions(staff_id);
create index commissions_sale_id_idx on commissions(sale_id);
create index commissions_status_idx on commissions(business_id, status);

create trigger commissions_set_updated_at
  before update on commissions
  for each row execute function set_updated_at();

-- ===== 0011_expenses.sql =====
create table expense_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger expense_categories_set_updated_at
  before update on expense_categories
  for each row execute function set_updated_at();

create table expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  category_id uuid references expense_categories(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  payment_method payment_method_enum not null default 'CASH',
  description text,
  expense_date date not null default current_date,
  created_by uuid not null references profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index expenses_business_id_idx on expenses(business_id);
create index expenses_category_id_idx on expenses(category_id);
create index expenses_date_idx on expenses(business_id, expense_date);

create trigger expenses_set_updated_at
  before update on expenses
  for each row execute function set_updated_at();

-- ===== 0012_settings.sql =====
-- Free-form per-business settings (receipt footer text, POS behavior
-- toggles, etc.) as key/value so new settings don't require a migration.
create table settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (business_id, key)
);

create trigger settings_set_updated_at
  before update on settings
  for each row execute function set_updated_at();

-- ===== 0013_audit_logs.sql =====
-- Audit trail. Insert-only from the application's perspective: RLS grants
-- SELECT to business admins and INSERT to any active member, but never
-- grants UPDATE or DELETE to anyone (see 0015_rls_policies.sql).
create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid references profiles(id) on delete set null,
  action audit_action not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_business_id_idx on audit_logs(business_id);
create index audit_logs_entity_idx on audit_logs(entity_type, entity_id);
create index audit_logs_created_at_idx on audit_logs(business_id, created_at);

-- ===== 0014_rls_helpers.sql =====
-- RLS helper functions.
--
-- These are SECURITY DEFINER so they can read business_members without
-- being subject to that table's own RLS policy (which would otherwise
-- recurse: the policy calls is_member(), which queries business_members,
-- which is itself RLS-protected). Each function only ever returns a
-- boolean/role for the CALLING user (auth.uid()) — it never exposes rows
-- the caller shouldn't see, so bypassing RLS internally is safe.
--
-- search_path is pinned to prevent search-path hijacking of a
-- SECURITY DEFINER function.

create or replace function role_rank(p_role business_role)
returns int
language sql
immutable
as $$
  select case p_role
    when 'OWNER' then 5
    when 'ADMIN' then 4
    when 'MANAGER' then 3
    when 'CASHIER' then 2
    when 'STAFF' then 1
  end;
$$;

create or replace function is_member(p_business_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from business_members
    where business_id = p_business_id
      and user_id = auth.uid()
      and active = true
  );
$$;

create or replace function member_role(p_business_id uuid)
returns business_role
language sql
security definer
set search_path = public
stable
as $$
  select role from business_members
  where business_id = p_business_id
    and user_id = auth.uid()
    and active = true
  limit 1;
$$;

create or replace function has_role_at_least(p_business_id uuid, p_min business_role)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(role_rank(member_role(p_business_id)) >= role_rank(p_min), false);
$$;

-- ===== 0015_rls_policies.sql =====
-- Enable RLS everywhere. No table is ever trusted to filter by business_id
-- supplied from the client — every check below re-derives membership from
-- business_members using auth.uid(), server-side.

alter table businesses enable row level security;
alter table branches enable row level security;
alter table profiles enable row level security;
alter table business_members enable row level security;
alter table customers enable row level security;
alter table customer_notes enable row level security;
alter table service_categories enable row level security;
alter table services enable row level security;
alter table product_categories enable row level security;
alter table products enable row level security;
alter table suppliers enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table payments enable row level security;
alter table inventory_movements enable row level security;
alter table commissions enable row level security;
alter table expense_categories enable row level security;
alter table expenses enable row level security;
alter table settings enable row level security;
alter table audit_logs enable row level security;

-- businesses ------------------------------------------------------------
-- No INSERT policy: businesses are only created via the
-- create_business_with_owner() SECURITY DEFINER function so the owner
-- membership is created atomically with the business.

create policy businesses_select on businesses
  for select using (is_member(id));

create policy businesses_update on businesses
  for update using (has_role_at_least(id, 'ADMIN'))
  with check (has_role_at_least(id, 'ADMIN'));

-- branches ----------------------------------------------------------------

create policy branches_select on branches
  for select using (is_member(business_id));

create policy branches_insert on branches
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy branches_update on branches
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy branches_delete on branches
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- profiles ------------------------------------------------------------------
-- No INSERT policy: rows are created by the handle_new_auth_user() trigger.
-- No DELETE policy: profiles are removed by cascading from auth.users.

create policy profiles_select on profiles
  for select using (
    id = auth.uid()
    or exists (
      select 1 from business_members mine
      join business_members theirs on theirs.business_id = mine.business_id
      where mine.user_id = auth.uid() and mine.active
        and theirs.user_id = profiles.id and theirs.active
    )
  );

create policy profiles_update on profiles
  for update using (id = auth.uid())
  with check (id = auth.uid());

-- business_members ----------------------------------------------------------
-- No INSERT policy for the initial OWNER row: that happens inside
-- create_business_with_owner(). Later invites go through the
-- invite_business_member() function so role-escalation rules are enforced
-- in one place instead of duplicated in RLS.

create policy business_members_select on business_members
  for select using (is_member(business_id));

-- An ADMIN may manage MANAGER/CASHIER/STAFF rows, but only an OWNER may
-- touch a row that is (or would become) OWNER/ADMIN — otherwise an ADMIN
-- could self-escalate or demote/remove an owner via a raw UPDATE.

create policy business_members_update on business_members
  for update using (
    has_role_at_least(business_id, 'ADMIN')
    and (role <> 'OWNER' or member_role(business_id) = 'OWNER')
  )
  with check (
    has_role_at_least(business_id, 'ADMIN')
    and (role not in ('OWNER', 'ADMIN') or member_role(business_id) = 'OWNER')
  );

create policy business_members_delete on business_members
  for delete using (
    has_role_at_least(business_id, 'ADMIN')
    and (role <> 'OWNER' or member_role(business_id) = 'OWNER')
  );

-- customers / customer_notes -------------------------------------------------

create policy customers_select on customers
  for select using (is_member(business_id));

create policy customers_insert on customers
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy customers_update on customers
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

create policy customers_delete on customers
  for delete using (has_role_at_least(business_id, 'ADMIN'));

create policy customer_notes_select on customer_notes
  for select using (is_member(business_id));

create policy customer_notes_insert on customer_notes
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

-- service_categories / services ----------------------------------------------

create policy service_categories_select on service_categories
  for select using (is_member(business_id));

create policy service_categories_write on service_categories
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy service_categories_update on service_categories
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy service_categories_delete on service_categories
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy services_select on services
  for select using (is_member(business_id));

create policy services_insert on services
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy services_update on services
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy services_delete on services
  for delete using (has_role_at_least(business_id, 'MANAGER'));

-- product_categories / products / suppliers ----------------------------------

create policy product_categories_select on product_categories
  for select using (is_member(business_id));

create policy product_categories_insert on product_categories
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy product_categories_update on product_categories
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy product_categories_delete on product_categories
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy products_select on products
  for select using (is_member(business_id));

create policy products_insert on products
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy products_update on products
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy products_delete on products
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_select on suppliers
  for select using (is_member(business_id));

create policy suppliers_insert on suppliers
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_update on suppliers
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_delete on suppliers
  for delete using (has_role_at_least(business_id, 'MANAGER'));

-- sales / sale_items ----------------------------------------------------------
-- No DELETE policy on either table, ever: sales are never hard-deleted
-- (see spec section 18/38) — void/refund is a status UPDATE instead.

create policy sales_select on sales
  for select using (is_member(business_id));

create policy sales_insert on sales
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy sales_update on sales
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy sale_items_select on sale_items
  for select using (is_member(business_id));

create policy sale_items_insert on sale_items
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

-- payments --------------------------------------------------------------------
-- No DELETE policy: payments are corrected via status updates, not removal.

create policy payments_select on payments
  for select using (is_member(business_id));

create policy payments_insert on payments
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy payments_update on payments
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

-- inventory_movements -----------------------------------------------------------
-- No UPDATE/DELETE policy: it is an append-only ledger. Corrections are new
-- offsetting movements (ADJUSTMENT), not edits to history.

create policy inventory_movements_select on inventory_movements
  for select using (is_member(business_id));

create policy inventory_movements_insert on inventory_movements
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

-- commissions -------------------------------------------------------------------

create policy commissions_select on commissions
  for select using (is_member(business_id));

create policy commissions_insert on commissions
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy commissions_update on commissions
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

-- expense_categories / expenses ---------------------------------------------------

create policy expense_categories_select on expense_categories
  for select using (is_member(business_id));

create policy expense_categories_insert on expense_categories
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy expense_categories_update on expense_categories
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy expense_categories_delete on expense_categories
  for delete using (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_select on expenses
  for select using (is_member(business_id));

create policy expenses_insert on expenses
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_update on expenses
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_delete on expenses
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- settings ------------------------------------------------------------------------

create policy settings_select on settings
  for select using (is_member(business_id));

create policy settings_insert on settings
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy settings_update on settings
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy settings_delete on settings
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- audit_logs ------------------------------------------------------------------------
-- No UPDATE/DELETE policy for anyone: the log is immutable from the client.

create policy audit_logs_select on audit_logs
  for select using (has_role_at_least(business_id, 'ADMIN'));

create policy audit_logs_insert on audit_logs
  for insert with check (
    is_member(business_id)
    and (user_id = auth.uid() or user_id is null)
  );

-- ===== 0016_business_onboarding.sql =====
-- Prevents removing or demoting the last remaining OWNER of a business,
-- which would otherwise lock everyone out of admin-level operations.
create or replace function guard_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining_owners int;
begin
  if (tg_op = 'DELETE' and old.role = 'OWNER' and old.active) or
     (tg_op = 'UPDATE' and old.role = 'OWNER' and old.active
        and (new.role <> 'OWNER' or new.active = false)) then
    select count(*) into remaining_owners
    from business_members
    where business_id = old.business_id
      and role = 'OWNER'
      and active = true
      and id <> old.id;

    if remaining_owners = 0 then
      raise exception 'Cannot remove or demote the last owner of a business';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger business_members_guard_last_owner
  before update or delete on business_members
  for each row execute function guard_last_owner();

-- Creates a business and its OWNER membership atomically. This is the only
-- way a business row can come into existence — there is no client-facing
-- INSERT policy on businesses (see 0015_rls_policies.sql) because a
-- membership can't be checked against a business that doesn't exist yet.
create or replace function create_business_with_owner(
  p_name text,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_currency text default 'LAK',
  p_timezone text default 'Asia/Vientiane'
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business businesses;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'Profile not found for current user';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Business name is required';
  end if;

  insert into businesses (name, phone, email, address, currency, timezone)
  values (trim(p_name), p_phone, p_email, p_address,
          coalesce(nullif(p_currency, ''), 'LAK'),
          coalesce(nullif(p_timezone, ''), 'Asia/Vientiane'))
  returning * into v_business;

  insert into business_members (business_id, user_id, role, active)
  values (v_business.id, auth.uid(), 'OWNER', true);

  insert into branches (business_id, name, active)
  values (v_business.id, 'Main Branch', true);

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (v_business.id, auth.uid(), 'CREATE', 'business', v_business.id, to_jsonb(v_business));

  return v_business;
end;
$$;

grant execute on function create_business_with_owner(text, text, text, text, text, text) to authenticated;

-- Adds (or reactivates) a member of an existing business. Role-escalation
-- rules mirror the business_members RLS policies: only an OWNER may grant
-- OWNER or ADMIN.
create or replace function invite_business_member(
  p_business_id uuid,
  p_user_id uuid,
  p_role business_role
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
begin
  v_caller_role := member_role(p_business_id);

  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to add members';
  end if;

  if p_role in ('OWNER', 'ADMIN') and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can assign this role';
  end if;

  if not exists (select 1 from profiles where id = p_user_id) then
    raise exception 'No such user';
  end if;

  insert into business_members (business_id, user_id, role, active)
  values (p_business_id, p_user_id, p_role, true)
  on conflict (business_id, user_id) do update
    set role = excluded.role, active = true
  returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, to_jsonb(v_member));

  return v_member;
end;
$$;

grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;

-- ===== 0017_pos_checkout.sql =====
-- The POS checkout transaction: sale + sale_items + payment + inventory
-- decrement + commission + customer stats + audit log, atomically.
--
-- SECURITY DEFINER so it can write across all of those tables in one
-- transaction, but it is NOT a blanket bypass of the authorization model:
-- it re-derives the caller's membership/role itself via
-- has_role_at_least(p_business_id, 'CASHIER') before doing anything, the
-- same way every RLS policy does — p_business_id is never trusted purely
-- because the client sent it. cashier_id is always auth.uid(), never
-- client-supplied, so a sale can't be attributed to someone else. The
-- subtotal/total are computed here from p_items, never accepted as a
-- client-sent number.
create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from sales
      where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal +
      (coalesce((v_item->>'unit_price')::numeric, 0) * coalesce((v_item->>'quantity')::int, 1))
      - coalesce((v_item->>'discount_amount')::numeric, 0);
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  v_total := v_subtotal - coalesce(p_discount_amount, 0) + coalesce(p_tax_amount, 0);
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  if coalesce(p_paid_amount, 0) >= v_total then
    v_payment_status := 'COMPLETED';
    v_change := p_paid_amount - v_total;
  else
    v_payment_status := 'PENDING';
    v_change := 0;
  end if;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), coalesce(p_tax_amount, 0), v_total,
    coalesce(p_paid_amount, 0), v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_item_subtotal :=
      (coalesce((v_item->>'unit_price')::numeric, 0) * coalesce((v_item->>'quantity')::int, 1))
      - coalesce((v_item->>'discount_amount')::numeric, 0);

    v_commission_amount := 0;
    v_service_commission_type := null;
    v_service_commission_value := null;

    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    if (v_item->>'item_type') = 'SERVICE' then
      select commission_type, commission_value
        into v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_staff_valid and v_service_commission_type is not null then
        if v_service_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_item_subtotal * coalesce(v_service_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_service_commission_value, 0);
        end if;
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', coalesce((v_item->>'quantity')::int, 1),
      coalesce((v_item->>'unit_price')::numeric, 0), coalesce((v_item->>'discount_amount')::numeric, 0),
      v_item_subtotal, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_product_stock is null then
        raise exception 'Product not found';
      end if;
      if v_product_stock < coalesce((v_item->>'quantity')::int, 1) then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      update products set stock_quantity = stock_quantity - coalesce((v_item->>'quantity')::int, 1)
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -coalesce((v_item->>'quantity')::int, 1), 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        v_service_commission_type, coalesce(v_service_commission_value, 0), v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, coalesce(p_paid_amount, 0), v_payment_status, auth.uid());

  if p_customer_id is not null then
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- ===== 0018_staff_invite_lookup.sql =====
-- Resolves an email address to a user_id so an ADMIN+ can invite an
-- existing account into their business via invite_business_member(),
-- which requires a user_id -- profiles carries no email column (email
-- lives only in auth.users), so without this there is no client-safe way
-- to turn "invite this email" into the user_id that RPC needs.
--
-- Deliberately NOT a general "find user by email" API:
--   - the caller must already be ADMIN+ of the SPECIFIC business they're
--     inviting into (p_business_id is a required, checked parameter, not
--     merely "some business" the caller happens to belong to);
--   - the only thing ever returned is a bare uuid or null -- never email,
--     name, phone, or any other auth.users field;
--   - unauthenticated/insufficiently-privileged callers are rejected via
--     the same has_role_at_least() check every other write path in this
--     schema uses, so auth.uid() being null or the caller lacking ADMIN+
--     both fail closed the same way invite_business_member() itself does.
--
-- Accepted, explicit tradeoff: an ADMIN can still learn "an account with
-- this email exists" for an email they try -- that is the inherent
-- minimum disclosure of any invite-by-email flow and is bounded to
-- authenticated ADMIN-tier members of a real business, not any caller.
create or replace function find_invitable_user_id(p_business_id uuid, p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_user_id uuid;
begin
  if not has_role_at_least(p_business_id, 'ADMIN') then
    raise exception 'Insufficient permission to look up invitable users';
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(trim(coalesce(p_email, '')))
  limit 1;

  return v_user_id;
end;
$$;

revoke execute on function find_invitable_user_id(uuid, text) from public;
grant execute on function find_invitable_user_id(uuid, text) to authenticated;

-- ===== 0019_revoke_anon_execute_on_staff_invite_lookup.sql =====
-- 0018 created find_invitable_user_id() and explicitly did:
--   revoke execute on function find_invitable_user_id(uuid, text) from public;
--   grant execute on function find_invitable_user_id(uuid, text) to authenticated;
--
-- Live verification after applying 0018 showed anon_can_execute = true
-- despite that REVOKE FROM PUBLIC. Root cause (confirmed via pg_default_acl):
-- this project's default privileges automatically grant EXECUTE on every
-- newly created function in the public schema to anon, authenticated, and
-- service_role as separate, explicit ACL entries -- applied at CREATE
-- FUNCTION time, independent of the PUBLIC pseudo-role. Revoking from
-- PUBLIC never touched that separate anon grant.
--
-- This migration closes that gap for this one function only. It is
-- intentionally NOT a database-wide default-privilege change (that would
-- affect every future function project-wide and still wouldn't
-- retroactively fix already-existing functions) -- a broader sweep across
-- all RPCs and the project's default-privilege configuration is tracked
-- as Day 6 ("Security + Hardening") work instead.
revoke execute on function find_invitable_user_id(uuid, text) from anon;

-- ===== 0020_inventory_stock_adjustment.sql =====
-- Manual stock adjustments (restock, correction, damage, expired), keeping
-- products.stock_quantity and inventory_movements consistent atomically --
-- the same problem complete_sale (0017) already solves for the SALE
-- movement type, applied here to the remaining movement types a MANAGER+
-- can record by hand. Without this RPC, a client would need two separate
-- writes (insert inventory_movements, update products.stock_quantity) with
-- no way to guarantee both happen or neither does if the connection drops
-- in between.
--
-- SECURITY DEFINER so it can write across both tables in one transaction,
-- but it re-derives the caller's role itself via
-- has_role_at_least(p_business_id, 'MANAGER') -- the same floor as
-- products_update/inventory_movements_insert RLS -- before doing anything;
-- p_business_id is never trusted purely because the client sent it, and
-- the product row is locked and re-checked against p_business_id so a
-- spoofed product_id from another tenant is rejected, not silently
-- adjusted.
--
-- Learned from 0018/0019: this project's default privileges grant EXECUTE
-- on every newly created public function to anon as a separate ACL entry,
-- independent of PUBLIC -- so anon is revoked explicitly here at creation
-- time instead of needing a follow-up migration.
create or replace function adjust_stock(
  p_business_id uuid,
  p_product_id uuid,
  p_branch_id uuid,
  p_movement_type inventory_movement_type,
  p_quantity_delta integer,
  p_note text
)
returns products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to adjust stock';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity must not be zero';
  end if;

  if p_movement_type = 'SALE' then
    raise exception 'SALE movements can only be recorded by complete_sale';
  end if;

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  if v_product.stock_quantity + p_quantity_delta < 0 then
    raise exception 'Adjustment would take % below zero stock', v_product.name;
  end if;

  update products set stock_quantity = stock_quantity + p_quantity_delta
    where id = p_product_id
    returning * into v_product;

  insert into inventory_movements (
    business_id, branch_id, product_id, movement_type, quantity,
    reference_type, note, created_by
  ) values (
    p_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta,
    'manual_adjustment', p_note, auth.uid()
  );

  return v_product;
end;
$$;

revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from public;
revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from anon;
grant execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) to authenticated;

-- ===== 0021_revoke_anon_execute_on_onboarding_and_checkout.sql =====
-- Day 6 security audit (F3): create_business_with_owner, invite_business_member,
-- and complete_sale were all created with `grant execute ... to authenticated`
-- but never an explicit `revoke ... from anon` -- the same default-privilege
-- gap 0019 already fixed for find_invitable_user_id and 0020 already avoided
-- for adjust_stock. Confirmed live (empirical anon RPC probe, matching the
-- technique 0019 itself used): all three returned the function's own
-- internal exception (P0001) to an unauthenticated caller instead of
-- Postgres's `42501 permission denied` -- proof anon currently holds
-- EXECUTE on all three.
--
-- This does not change any authorization or business rule already enforced
-- inside these functions -- every legitimate authenticated caller is
-- completely unaffected. It closes the ACL-level backstop so an anonymous
-- caller is rejected by Postgres itself, before the function body (and its
-- internal checks) ever runs, exactly like find_invitable_user_id/
-- adjust_stock already are.
revoke execute on function create_business_with_owner(text, text, text, text, text, text) from public;
revoke execute on function create_business_with_owner(text, text, text, text, text, text) from anon;
grant execute on function create_business_with_owner(text, text, text, text, text, text) to authenticated;

revoke execute on function invite_business_member(uuid, uuid, business_role) from public;
revoke execute on function invite_business_member(uuid, uuid, business_role) from anon;
grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;

revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- F3 also flagged that invite_business_member (unlike create_business_with_owner
-- and complete_sale) has no explicit `auth.uid() is null` guard -- it only
-- rejects an anonymous caller implicitly, because member_role(p_business_id)
-- happens to return null when auth.uid() is null, which then fails the
-- role-rank check below. That is correct today, but it is more fragile than
-- an explicit guard and inconsistent with every other RPC's style. This
-- redeclares the function with the same guard added at the top and every
-- other line identical to 0016's original -- no authorization or business
-- rule changes.
create or replace function invite_business_member(
  p_business_id uuid,
  p_user_id uuid,
  p_role business_role
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);

  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to add members';
  end if;

  if p_role in ('OWNER', 'ADMIN') and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can assign this role';
  end if;

  if not exists (select 1 from profiles where id = p_user_id) then
    raise exception 'No such user';
  end if;

  insert into business_members (business_id, user_id, role, active)
  values (p_business_id, p_user_id, p_role, true)
  on conflict (business_id, user_id) do update
    set role = excluded.role, active = true
  returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, to_jsonb(v_member));

  return v_member;
end;
$$;

-- CREATE OR REPLACE preserves the function's existing GRANT/REVOKE state as
-- long as its signature is unchanged (it is, here), but the grant is
-- restated below for clarity and to be self-contained regardless of
-- migration-application order.
revoke execute on function invite_business_member(uuid, uuid, business_role) from public;
revoke execute on function invite_business_member(uuid, uuid, business_role) from anon;
grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;

-- ===== 0022_protect_financial_snapshot_columns.sql =====
-- Day 6 security audit (F1): sales_update, payments_update, and
-- commissions_update (0015_rls_policies.sql) correctly gate WHO may update
-- a row (MANAGER+/ADMIN+), but RLS is row-level, not column-level -- none
-- of the three policies restrict WHICH columns a permitted caller may
-- change. That means a MANAGER+/ADMIN+ session used directly against the
-- REST API (not through this app, which never does this -- confirmed no
-- repository performs such an update) could rewrite total_amount,
-- paid_amount, commission_amount, staff attribution, or even
-- idempotency_key on an existing row, bypassing every guarantee
-- complete_sale established at creation time.
--
-- This does not touch the RLS policies themselves (no policy is weakened
-- or replaced) and does not touch complete_sale, since complete_sale only
-- ever INSERTs into these three tables, never UPDATEs an existing row --
-- confirmed by inspection of 0017_pos_checkout.sql. These triggers fire on
-- UPDATE only, so the Day 2 checkout path is entirely unaffected.
--
-- Each trigger blocks changes to the server-computed/snapshot/attribution
-- columns and explicitly allows the columns that represent a legitimate
-- status/void-metadata transition (the model this project's own plan
-- describes for the not-yet-built void_sale flow: "status update +
-- inventory reversal + commission reversal + audit log", i.e. state
-- transitions on existing rows, not raw field edits). This does not
-- implement or design that refund/void workflow -- it only ensures that
-- whenever it lands, it (and today's role-gated status changes) can still
-- update `status`/void metadata while financial history stays immutable.

create or replace function protect_sales_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.branch_id is distinct from old.branch_id
     or new.customer_id is distinct from old.customer_id
     or new.cashier_id is distinct from old.cashier_id
     or new.receipt_number is distinct from old.receipt_number
     or new.subtotal is distinct from old.subtotal
     or new.discount_amount is distinct from old.discount_amount
     or new.tax_amount is distinct from old.tax_amount
     or new.total_amount is distinct from old.total_amount
     or new.paid_amount is distinct from old.paid_amount
     or new.change_amount is distinct from old.change_amount
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial, attribution, or identity fields on an existing sale -- only status and void metadata may be updated';
  end if;
  return new;
end;
$$;

create trigger sales_protect_snapshot_columns
  before update on sales
  for each row execute function protect_sales_snapshot_columns();

create or replace function protect_payments_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.sale_id is distinct from old.sale_id
     or new.payment_method is distinct from old.payment_method
     or new.amount is distinct from old.amount
     or new.reference is distinct from old.reference
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial or identity fields on an existing payment -- only status may be updated';
  end if;
  return new;
end;
$$;

create trigger payments_protect_snapshot_columns
  before update on payments
  for each row execute function protect_payments_snapshot_columns();

create or replace function protect_commissions_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.sale_id is distinct from old.sale_id
     or new.sale_item_id is distinct from old.sale_item_id
     or new.staff_id is distinct from old.staff_id
     or new.commission_type is distinct from old.commission_type
     or new.commission_rate is distinct from old.commission_rate
     or new.commission_amount is distinct from old.commission_amount
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify commission amount, rate, or attribution on an existing commission -- only status may be updated';
  end if;
  return new;
end;
$$;

create trigger commissions_protect_snapshot_columns
  before update on commissions
  for each row execute function protect_commissions_snapshot_columns();

-- ===== 0023_complete_sale_customer_integrity.sql =====
-- Day 6 security audit (F2 + F4). Grouped in one migration because both
-- require a full CREATE OR REPLACE of complete_sale's body -- splitting
-- them would force one migration to silently restate the other's change,
-- which is a worse audit trail than one migration containing both.
--
-- F2: customers.total_spent/visit_count/last_visit_at are running totals
-- complete_sale maintains (0017_pos_checkout.sql:184-189), but
-- customers_update RLS (0015_rls_policies.sql) is CASHIER+ with no column
-- restriction, so any CASHIER+ session against the raw REST API could
-- overwrite these three columns directly. They cannot simply be
-- always-blocked-on-UPDATE, because complete_sale's own legitimate update
-- must still work.
--
-- Mechanism: complete_sale sets a transaction-local flag
-- (set_config(..., is_local => true)) immediately before its customer-stats
-- UPDATE; a new BEFORE UPDATE trigger on customers only allows changes to
-- those three columns while that flag is set. This is safe because the
-- client cannot establish the same trusted context: set_config is a
-- pg_catalog builtin, never exposed as a PostgREST RPC endpoint (PostgREST
-- only exposes functions from the public schema), and no REST table
-- operation (PATCH/POST/etc.) can execute arbitrary SQL ahead of itself --
-- a direct client UPDATE to /customers always runs in its own transaction
-- where the flag was never set, so it is rejected. is_local => true means
-- the flag automatically reverts at the end of complete_sale's own
-- transaction (one PostgREST request = one transaction), so nothing
-- leaks between requests.
--
-- F4: p_customer_id was inserted into sales.customer_id with no check that
-- the customer belongs to p_business_id -- unlike service_id, product_id,
-- and staff_id in the same function, which are all re-validated. Adds the
-- same style of check used for staff_id.
--
-- Every other line of complete_sale is unchanged from 0017. No checkout
-- calculation, idempotency behavior, or existing authorization rule is
-- altered.

create or replace function protect_customer_lifetime_metrics()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.total_spent is distinct from old.total_spent
      or new.visit_count is distinct from old.visit_count
      or new.last_visit_at is distinct from old.last_visit_at)
     and coalesce(current_setting('app.trusted_customer_stats_update', true), 'false') <> 'true'
  then
    raise exception 'total_spent, visit_count, and last_visit_at can only be updated by complete_sale';
  end if;
  return new;
end;
$$;

create trigger customers_protect_lifetime_metrics
  before update on customers
  for each row execute function protect_customer_lifetime_metrics();

create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from sales
      where business_id = p_business_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal +
      (coalesce((v_item->>'unit_price')::numeric, 0) * coalesce((v_item->>'quantity')::int, 1))
      - coalesce((v_item->>'discount_amount')::numeric, 0);
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  v_total := v_subtotal - coalesce(p_discount_amount, 0) + coalesce(p_tax_amount, 0);
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  if coalesce(p_paid_amount, 0) >= v_total then
    v_payment_status := 'COMPLETED';
    v_change := p_paid_amount - v_total;
  else
    v_payment_status := 'PENDING';
    v_change := 0;
  end if;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), coalesce(p_tax_amount, 0), v_total,
    coalesce(p_paid_amount, 0), v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_item_subtotal :=
      (coalesce((v_item->>'unit_price')::numeric, 0) * coalesce((v_item->>'quantity')::int, 1))
      - coalesce((v_item->>'discount_amount')::numeric, 0);

    v_commission_amount := 0;
    v_service_commission_type := null;
    v_service_commission_value := null;

    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    if (v_item->>'item_type') = 'SERVICE' then
      select commission_type, commission_value
        into v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_staff_valid and v_service_commission_type is not null then
        if v_service_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_item_subtotal * coalesce(v_service_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_service_commission_value, 0);
        end if;
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', coalesce((v_item->>'quantity')::int, 1),
      coalesce((v_item->>'unit_price')::numeric, 0), coalesce((v_item->>'discount_amount')::numeric, 0),
      v_item_subtotal, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_product_stock is null then
        raise exception 'Product not found';
      end if;
      if v_product_stock < coalesce((v_item->>'quantity')::int, 1) then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      update products set stock_quantity = stock_quantity - coalesce((v_item->>'quantity')::int, 1)
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -coalesce((v_item->>'quantity')::int, 1), 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        v_service_commission_type, coalesce(v_service_commission_value, 0), v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, coalesce(p_paid_amount, 0), v_payment_status, auth.uid());

  if p_customer_id is not null then
    perform set_config('app.trusted_customer_stats_update', 'true', true);
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

-- CREATE OR REPLACE preserves the existing GRANT/REVOKE state set by 0021
-- (same signature, so no privilege reset occurs); restated here for
-- clarity and to be self-contained regardless of migration-application
-- order.
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- ===== 0024_complete_sale_price_and_payment_integrity.sql =====
-- Day 7 audit (F7-1 CRITICAL, F7-2 HIGH, F7-3 MEDIUM). Redeclares complete_sale
-- with three fixes; every other authorization/validation rule from 0017/0023
-- is preserved verbatim (auth.uid() guard, has_role_at_least('CASHIER'),
-- service_id/product_id/staff_id/customer_id tenant validation, the
-- inventory FOR UPDATE lock, the customer-stats trusted-context flag from
-- 0023, and the SECURITY DEFINER/search_path/EXECUTE privilege hardening
-- from 0021 -- none of that is touched here).
--
-- F7-1: unit_price was previously taken verbatim from the client-supplied
-- p_items, with no cross-check against services.price / products.
-- selling_price. That let a CASHIER-rank caller (a real, authenticated
-- session -- not an ACL bypass) forge an arbitrary price, which fed
-- directly into sale_items.unit_price/subtotal, sales.total_amount, AND
-- commission_amount (commission is computed off the item subtotal). Fixed
-- by resolving the authoritative catalog price server-side for every line
-- and using ONLY that value for every downstream calculation -- the
-- client's unit_price field is now read from p_items only for backward
-- wire-compatibility and is never used for anything.
--
-- Implementation note: complete_sale already needed two passes over
-- p_items (pass 1 computes the sale's own subtotal/total before the sales
-- row can be inserted, since sale_items.sale_id requires that row to
-- already exist; pass 2 does the per-item inserts/stock deduction/
-- commission). To avoid resolving -- and therefore querying -- the price
-- twice (which could theoretically observe two different prices if a
-- price edit landed between the two passes), pass 1 now resolves each
-- item exactly once into an in-memory v_resolved_items array (locking
-- product rows with FOR UPDATE at that point, held for the rest of the
-- transaction) and pass 2 consumes that array instead of re-querying
-- services/products. Pass 2 still re-reads products.stock_quantity
-- immediately before deducting it (the lock from pass 1 is already held,
-- so this is an uncontended, cheap read) and still performs the
-- check-then-deduct for stock sufficiency in that same second pass, in
-- the same order as before -- this preserves the original behavior for a
-- cart that references the same product in two separate lines (each
-- line's deduction is visible to the next line's check within the same
-- transaction, exactly as pre-fix).
--
-- F7-2: p_paid_amount was only used to pick between payment_status
-- COMPLETED/PENDING; sales.status was hardcoded to 'COMPLETED' either way,
-- so a sale with $0 paid was fully processed (inventory deducted,
-- commission accrued, customer stats updated) with no distinguishing
-- marker beyond an easy-to-miss payment_status column. Per explicit
-- product decision (no deferred/credit-payment system is being
-- introduced), payment must now cover the total or the entire sale is
-- rejected before any persistence: NULL, negative, or amount < v_total
-- are all rejected with a clear business error, computed only after
-- v_total itself is computed from authoritative prices. Overpayment
-- (change) behavior is unchanged.
--
-- F7-3: p_idempotency_key was only checked for duplicates when NOT NULL --
-- a caller could omit it entirely and bypass replay protection altogether.
-- It is now mandatory; NULL is rejected immediately. The existing
-- unique(business_id, idempotency_key) constraint (0007_sales.sql) needs
-- no change: it already enforces uniqueness for every non-null key, and
-- NULL can no longer reach the INSERT.
create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_resolved_items jsonb := '[]'::jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_unit_price numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
  v_quantity integer;
  v_discount numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  -- Pass 1: resolve each item's authoritative catalog price exactly once
  -- (never the client-supplied unit_price) and accumulate the sale's
  -- subtotal from those authoritative values.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::int, 1);
    v_discount := coalesce((v_item->>'discount_amount')::numeric, 0);
    v_service_commission_type := null;
    v_service_commission_value := null;

    if (v_item->>'item_type') = 'SERVICE' then
      select price, commission_type, commission_value
        into v_unit_price, v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_unit_price is null then
        raise exception 'Service not found in this business';
      end if;
    elsif (v_item->>'item_type') = 'PRODUCT' then
      select selling_price into v_unit_price
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_unit_price is null then
        raise exception 'Product not found in this business';
      end if;
    else
      raise exception 'Invalid item type';
    end if;

    v_item_subtotal := (v_unit_price * v_quantity) - v_discount;
    if v_item_subtotal < 0 then
      raise exception 'Discount cannot exceed the item subtotal';
    end if;

    v_subtotal := v_subtotal + v_item_subtotal;

    v_resolved_items := v_resolved_items || jsonb_build_object(
      'item_type', v_item->>'item_type',
      'service_id', nullif(v_item->>'service_id', ''),
      'product_id', nullif(v_item->>'product_id', ''),
      'staff_id', v_item->>'staff_id',
      'name_snapshot', v_item->>'name_snapshot',
      'quantity', v_quantity,
      'unit_price', v_unit_price,
      'discount_amount', v_discount,
      'item_subtotal', v_item_subtotal,
      'commission_type', v_service_commission_type,
      'commission_value', v_service_commission_value
    );
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  v_total := v_subtotal - coalesce(p_discount_amount, 0) + coalesce(p_tax_amount, 0);
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount < v_total then
    raise exception 'Payment amount cannot be less than the sale total';
  end if;

  v_payment_status := 'COMPLETED';
  v_change := p_paid_amount - v_total;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), coalesce(p_tax_amount, 0), v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  -- Pass 2: persist each line using the already-resolved authoritative
  -- price/subtotal from pass 1 -- no re-query of services/products for
  -- price. Stock sufficiency is still checked and deducted here, in the
  -- same order as before the fix, so two lines referencing the same
  -- product still interact correctly (the lock was already taken in
  -- pass 1, so this re-read is immediate, not blocking).
  for v_item in select * from jsonb_array_elements(v_resolved_items)
  loop
    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    v_commission_amount := 0;
    if (v_item->>'item_type') = 'SERVICE' and v_staff_valid and (v_item->>'commission_type') is not null then
      if (v_item->>'commission_type') = 'PERCENTAGE' then
        v_commission_amount := round(
          (v_item->>'item_subtotal')::numeric * coalesce((v_item->>'commission_value')::numeric, 0) / 100, 2
        );
      else
        v_commission_amount := coalesce((v_item->>'commission_value')::numeric, 0);
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric, (v_item->>'discount_amount')::numeric,
      (v_item->>'item_subtotal')::numeric, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid
        for update;

      if v_product_stock < (v_item->>'quantity')::int then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      update products set stock_quantity = stock_quantity - (v_item->>'quantity')::int
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -(v_item->>'quantity')::int, 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        (v_item->>'commission_type')::commission_kind, coalesce((v_item->>'commission_value')::numeric, 0),
        v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, v_payment_status, auth.uid());

  if p_customer_id is not null then
    perform set_config('app.trusted_customer_stats_update', 'true', true);
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

-- CREATE OR REPLACE preserves the existing GRANT/REVOKE state set by 0021
-- (same signature, so no privilege reset occurs); restated here for
-- clarity and to be self-contained regardless of migration-application
-- order. anon/public EXECUTE remain revoked; only authenticated retains
-- access.
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- ===== 0025_revoke_direct_financial_insert_paths.sql =====
-- Day 8 audit (F8-1 CRITICAL, F8-2 HIGH, F8-3 HIGH, F8-4 MEDIUM, F8-5
-- MEDIUM): sales_insert, sale_items_insert, payments_insert,
-- commissions_insert, and inventory_movements_insert (0015_rls_policies.sql)
-- were all role-gated only ("has_role_at_least(business_id, X)"), with no
-- validation of the values being inserted or their relationship to other
-- rows. That let an authenticated CASHIER+/ADMIN+/MANAGER+ session bypass
-- complete_sale/adjust_stock entirely via a direct REST INSERT --
-- fabricating an arbitrary sale with no items, injecting a retroactive
-- line item into an existing (even closed) sale with a forged price,
-- fabricating a commission payout unconnected to any real sale, inserting
-- a phantom payment, or fabricating an inventory ledger entry that never
-- moved real stock. This defeated every integrity control Day 7 built
-- into complete_sale, since that function is only one path into these
-- tables -- the tables themselves remained directly writable.
--
-- Fix: remove the client-facing INSERT policy on all five tables
-- entirely, so no role satisfies any INSERT policy on them and Postgres's
-- default-deny applies. This is the same, already-proven-safe pattern
-- this project already uses for `businesses` (see 0015_rls_policies.sql:
-- "No INSERT policy: businesses are only created via the
-- create_business_with_owner() SECURITY DEFINER function") and for the
-- initial `business_members` OWNER row -- complete_sale and adjust_stock
-- are SECURITY DEFINER functions owned by a role that bypasses RLS for
-- its own writes (the same reason create_business_with_owner has always
-- been able to insert into `businesses` despite no policy ever existing
-- there), so removing these policies does not require touching either
-- function and does not change their behavior for a legitimate caller in
-- any way.
--
-- SELECT/UPDATE/DELETE policies on all five tables are completely
-- untouched: sales_select/sales_update, sale_items_select (no
-- UPDATE/DELETE policy existed or exists), payments_select/
-- payments_update, commissions_select/commissions_update,
-- inventory_movements_select (no UPDATE/DELETE policy existed or exists)
-- all remain exactly as they were. The Day 6 column-protection triggers
-- on sales/payments/commissions (0022_protect_financial_snapshot_columns.sql)
-- are BEFORE UPDATE triggers and are unaffected either way.
--
-- Intended end state:
--   direct authenticated REST INSERT -> sales/sale_items/payments/
--     commissions/inventory_movements: DENIED for every role
--   complete_sale() -> still succeeds (inserts all five tables internally)
--   adjust_stock() -> still succeeds (inserts inventory_movements internally)
drop policy sales_insert on sales;
drop policy sale_items_insert on sale_items;
drop policy payments_insert on payments;
drop policy inventory_movements_insert on inventory_movements;
drop policy commissions_insert on commissions;

-- ===== 0026_void_sale.sql =====
-- F9-2 (Finalization Phase audit, forensic report dated 2026-08-30): adds
-- the previously-missing void flow (COMPLETED -> VOIDED only; REFUNDED
-- stays deferred -- no partial-refund schema exists, this is scoped
-- exactly as a whole-sale cancellation).
--
-- The audit found that the schema already anticipated this feature --
-- sales.void_reason/voided_by/voided_at and the VOIDED/REFUNDED sale_status
-- values, the VOID/REFUND audit_action values, and commissions.REVERSED
-- have all existed since 0001/0007, unused until now -- so this migration
-- needs no new columns or enum values (movement_type reuses the existing
-- RETURN value; reference_type/reference_id disambiguate a void reversal
-- from a genuine customer return).
--
-- The audit also found two CRITICAL live bypasses, closed here as part of
-- the same change rather than as a follow-up:
--
--   C1: sales_update (0015_rls_policies.sql) let any MANAGER+ PATCH
--   status/void_reason/voided_by/voided_at directly via REST -- the 0022
--   column-protection trigger deliberately allows exactly those columns
--   in anticipation of this feature, but nothing enforced inventory
--   reversal, commission reversal, or an audit record alongside it. No
--   repository in lib/ has ever used this policy (confirmed by inspection
--   before writing this migration), so dropping it costs the app nothing.
--
--   C2: payments_update (0015_rls_policies.sql) let any MANAGER+ PATCH
--   payments.status directly, same unused-by-the-app, same lack of any
--   linkage or audit trail.
--
--   H1: audit_logs_insert (0015_rls_policies.sql) had no role gate at all
--   -- any authenticated business member could insert a fabricated
--   action='VOID' row with arbitrary old_data/new_data, independent of
--   whether a real void ever happened. No repository in lib/ inserts into
--   audit_logs directly (only complete_sale's SECURITY DEFINER insert
--   does, which bypasses RLS anyway and is unaffected by dropping this
--   policy).
--
-- void_sale() follows the exact pattern already proven safe by
-- complete_sale (0024) and adjust_stock (0020): auth.uid() guard,
-- has_role_at_least(p_business_id, 'MANAGER') (role_rank: MANAGER=3,
-- ADMIN=4, OWNER=5 all satisfy this; CASHIER=2/STAFF=1 do not), the target
-- sale is looked up scoped by BOTH id and business_id so a cross-tenant
-- sale_id is indistinguishable from "not found", and the sale row is
-- locked with `for update` before its status is checked -- this is the
-- single serialization point that makes two concurrent void_sale calls on
-- the same sale resolve to exactly one success: the second caller blocks
-- on the lock, then observes status = 'VOIDED' once it resumes and raises
-- before touching inventory/commissions/payments/audit_logs.
--
-- Per-line inventory reversal locks each product row with `for update`
-- (same as adjust_stock/complete_sale) and inserts exactly one
-- inventory_movements row per PRODUCT line with a live product_id.
-- sale_items.product_id can be null if the product was later hard-deleted
-- (products_delete has no dependency check against sale history) -- that
-- line is skipped, not treated as a failure, and the skip is recorded in
-- the audit metadata rather than silently dropped.
--
-- Commission reversal is a single status-only UPDATE (status = 'REVERSED'
-- where not already reversed) -- commission_amount/commission_rate/
-- staff_id/sale_item_id are untouched (also structurally blocked by the
-- 0022 protect_commissions_snapshot_columns trigger, which this bypasses
-- as SECURITY DEFINER but is not fighting: the RPC simply never writes
-- those columns). Reports already exclude REVERSED commissions
-- (reports_repository.dart: .neq('status', 'REVERSED')) and already
-- filter sales/dailyRevenue/salesForRange to status = 'COMPLETED' --
-- neither needs to change.
--
-- Payment reversal is bookkeeping only: payments.status = 'REFUNDED' for
-- the sale's payment row(s); amount/payment_method/reference/created_by
-- are never written by this function, so they remain exactly what was
-- recorded at sale time. No payment-gateway call, no partial-refund
-- amount -- out of scope per the frozen F9-2 design decision.
--
-- The audit_logs insert is the last statement before RETURN, inside the
-- same transaction as every mutation above it -- any failure at any
-- earlier step rolls back the whole transaction, including this insert,
-- so a failed void can never leave behind a record claiming it succeeded.
create or replace function void_sale(
  p_business_id uuid,
  p_sale_id uuid,
  p_reason text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_old_sale jsonb;
  v_item record;
  v_product products;
  v_reversed_commission_count int := 0;
  v_reversed_inventory_count int := 0;
  v_skipped_product_deleted_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to void a sale';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A void reason is required';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Only a completed sale can be voided';
  end if;

  v_old_sale := to_jsonb(v_sale);

  for v_item in
    select * from sale_items where sale_id = p_sale_id and item_type = 'PRODUCT'
  loop
    if v_item.product_id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    select * into v_product from products
      where id = v_item.product_id and business_id = p_business_id
      for update;

    if v_product.id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    update products set stock_quantity = stock_quantity + v_item.quantity
      where id = v_item.product_id;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, reference_id, note, created_by
    ) values (
      p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_item.quantity,
      'sale_void', p_sale_id, 'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
    );

    v_reversed_inventory_count := v_reversed_inventory_count + 1;
  end loop;

  update commissions set status = 'REVERSED'
    where sale_id = p_sale_id and status <> 'REVERSED';
  get diagnostics v_reversed_commission_count = row_count;

  update sales set
    status = 'VOIDED',
    void_reason = p_reason,
    voided_by = auth.uid(),
    voided_at = now()
    where id = p_sale_id
    returning * into v_sale;

  update payments set status = 'REFUNDED'
    where sale_id = p_sale_id and status <> 'REFUNDED';

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'VOID', 'sale', p_sale_id, v_old_sale, to_jsonb(v_sale),
    jsonb_build_object(
      'reason', p_reason,
      'reversed_commission_count', v_reversed_commission_count,
      'reversed_inventory_line_count', v_reversed_inventory_count,
      'skipped_product_deleted_lines', v_skipped_product_deleted_count
    )
  );

  return v_sale;
end;
$$;

revoke execute on function void_sale(uuid, uuid, text) from public;
revoke execute on function void_sale(uuid, uuid, text) from anon;
grant execute on function void_sale(uuid, uuid, text) to authenticated;

-- C1/C2/H1: close the live direct-write bypasses now that void_sale is the
-- sole sanctioned path for these transitions. Confirmed unused by any
-- repository in lib/ before dropping. commissions_update is intentionally
-- left untouched -- it is a separate, pre-existing, actively used path
-- (CommissionRepository.updateStatus, ADMIN+) and is outside F9-2 scope.
drop policy sales_update on sales;
drop policy payments_update on payments;
drop policy audit_logs_insert on audit_logs;

-- ===== 0027_audit_log_coverage.sql =====
-- F9-3 (Finalization Phase audit, "Audit logs wired to every mutation" --
-- POS_IMPLEMENTATION_PLAN.md's own outstanding checklist item). Closes the
-- two remaining sensitive, unaudited write paths and the two direct-write
-- bypasses they created, following the exact pattern F9-2's void_sale
-- established: SECURITY DEFINER RPC + close the direct-write RLS path that
-- would otherwise let a caller skip the audit trail entirely.
--
-- 1) adjust_stock (0020_inventory_stock_adjustment.sql) was already
--    SECURITY DEFINER but never wrote to audit_logs, despite
--    'STOCK_ADJUSTMENT' existing in the audit_action enum since 0001
--    specifically for this. Redeclared here (same signature -- no
--    privilege reset) to capture the product's stock_quantity before/after
--    and log one STOCK_ADJUSTMENT row per successful call, alongside its
--    existing inventory_movements row. No other behavior changes: the same
--    auth.uid()/has_role_at_least('MANAGER') guard, the same
--    quantity/SALE-type/not-found/negative-stock validation, and the same
--    inventory_movements insert, all verbatim from 0020.
--
-- 2) StaffRepository.updateRole/setActive (lib/features/staff/data/
--    staff_repository.dart) were direct `business_members` UPDATEs.
--    business_members_update RLS (0015_rls_policies.sql) already gates
--    these correctly (ADMIN+, and an ADMIN cannot touch or promote to an
--    OWNER/ADMIN row -- only an OWNER can), but a role/active change made
--    through that policy left no audit_logs row at all. Inspected every
--    caller of business_members_update before touching it: only those two
--    StaffRepository methods use it (confirmed via repo-wide grep for
--    `.from('business_members')` -- every other call site is a read).
--
--    set_member_role/set_member_active reproduce the exact same
--    authorization shape as business_members_update's USING/WITH CHECK
--    (also identical in spirit to invite_business_member's own
--    role-escalation guard, already proven correct in this codebase):
--      - caller must be ADMIN+ in the target business
--      - a caller who is not OWNER cannot modify a row that is currently
--        OWNER (mirrors USING's "role <> 'OWNER' or caller is OWNER")
--      - only an OWNER caller may assign OWNER or ADMIN (mirrors WITH
--        CHECK and invite_business_member's own rule) -- this is what
--        makes self- and peer-escalation to OWNER/ADMIN impossible via
--        this path, exactly as it was impossible via the old direct
--        UPDATE
--    guard_last_owner (0016_business_onboarding.sql) is a BEFORE UPDATE
--    trigger, unaffected either way -- it still fires on every UPDATE this
--    RPC performs and still blocks removing/demoting a business's last
--    OWNER regardless of caller.
--
--    Once both RPCs exist, business_members_update is dropped entirely:
--    with StaffRepository migrated to call them instead, no legitimate
--    caller depends on the policy any more, and leaving it in place would
--    let a direct REST PATCH reproduce the same role/active change while
--    skipping the audit_logs insert -- exactly the C1/C2 class of bug F9-2
--    closed for sales/payments. SELECT and the OWNER-row DELETE guard are
--    untouched.
--
-- Intended end state:
--   adjust_stock -> still succeeds exactly as before, plus one
--     STOCK_ADJUSTMENT audit_logs row
--   direct authenticated PATCH business_members (role or active) -> DENIED
--     for every role (0 rows, RLS)
--   set_member_role/set_member_active -> succeed for ADMIN+ (subject to
--     the same OWNER-row/escalation rules as before), each producing
--     exactly one PERMISSION_CHANGE audit_logs row in the same transaction
--   anon EXECUTE on either new function -> DENIED (42501)

create or replace function adjust_stock(
  p_business_id uuid,
  p_product_id uuid,
  p_branch_id uuid,
  p_movement_type inventory_movement_type,
  p_quantity_delta integer,
  p_note text
)
returns products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
  v_before_stock integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to adjust stock';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity must not be zero';
  end if;

  if p_movement_type = 'SALE' then
    raise exception 'SALE movements can only be recorded by complete_sale';
  end if;

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  v_before_stock := v_product.stock_quantity;

  if v_product.stock_quantity + p_quantity_delta < 0 then
    raise exception 'Adjustment would take % below zero stock', v_product.name;
  end if;

  update products set stock_quantity = stock_quantity + p_quantity_delta
    where id = p_product_id
    returning * into v_product;

  insert into inventory_movements (
    business_id, branch_id, product_id, movement_type, quantity,
    reference_type, note, created_by
  ) values (
    p_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta,
    'manual_adjustment', p_note, auth.uid()
  );

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'STOCK_ADJUSTMENT', 'product', p_product_id,
    jsonb_build_object('stock_quantity', v_before_stock),
    jsonb_build_object('stock_quantity', v_product.stock_quantity),
    jsonb_build_object('movement_type', p_movement_type, 'quantity_delta', p_quantity_delta, 'note', p_note)
  );

  return v_product;
end;
$$;

revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from public;
revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from anon;
grant execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) to authenticated;

create or replace function set_member_role(
  p_business_id uuid,
  p_target_user_id uuid,
  p_role business_role
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);
  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to change member roles';
  end if;

  select * into v_member from business_members
    where business_id = p_business_id and user_id = p_target_user_id
    for update;

  if v_member.id is null then
    raise exception 'Member not found in this business';
  end if;

  if v_member.role = 'OWNER' and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can modify an owner';
  end if;

  if p_role in ('OWNER', 'ADMIN') and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can assign this role';
  end if;

  v_old_data := to_jsonb(v_member);

  update business_members set role = p_role
    where business_id = p_business_id and user_id = p_target_user_id
    returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, v_old_data, to_jsonb(v_member));

  return v_member;
end;
$$;

revoke execute on function set_member_role(uuid, uuid, business_role) from public;
revoke execute on function set_member_role(uuid, uuid, business_role) from anon;
grant execute on function set_member_role(uuid, uuid, business_role) to authenticated;

create or replace function set_member_active(
  p_business_id uuid,
  p_target_user_id uuid,
  p_active boolean
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);
  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to change member status';
  end if;

  select * into v_member from business_members
    where business_id = p_business_id and user_id = p_target_user_id
    for update;

  if v_member.id is null then
    raise exception 'Member not found in this business';
  end if;

  if v_member.role = 'OWNER' and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can deactivate or reactivate an owner';
  end if;

  v_old_data := to_jsonb(v_member);

  update business_members set active = p_active
    where business_id = p_business_id and user_id = p_target_user_id
    returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, v_old_data, to_jsonb(v_member));

  return v_member;
end;
$$;

revoke execute on function set_member_active(uuid, uuid, boolean) from public;
revoke execute on function set_member_active(uuid, uuid, boolean) from anon;
grant execute on function set_member_active(uuid, uuid, boolean) to authenticated;

-- Confirmed unused by any other repository (see header) -- close the
-- direct-write bypass now that both RPCs cover its legitimate uses.
drop policy business_members_update on business_members;

-- ===== 0028_business_settings_rpc.sql =====
-- F9-4 (Finalization Phase audit, "Business settings" -- the permission
-- matrix in POS_IMPLEMENTATION_PLAN.md reserves OWNER/ADMIN access for
-- this, and the planned lib/features/settings/ folder was never built).
-- Adds the missing write path for the businesses table's own profile
-- fields (name/phone/email/address/currency/tax_enabled/tax_rate/
-- logo_url), following the exact SECURITY DEFINER RPC + audit + policy-
-- closure pattern already proven twice in this codebase (F9-2's
-- void_sale, F9-3's set_member_role/set_member_active).
--
-- businesses_update (0015_rls_policies.sql) already gates writes to
-- ADMIN+, correctly and with no column restriction needed (unlike sales/
-- payments/commissions, nothing on this table is a computed/snapshot
-- value that a legitimate caller must be prevented from touching -- every
-- column here is exactly what ADMIN+ is meant to edit). But it has never
-- been used by any repository (confirmed by inspection: businesses is
-- only ever read via BusinessRepository.myMemberships()'s join and
-- written via create_business_with_owner's RPC insert -- no direct
-- .update() call exists anywhere in lib/), so it has stood as a live,
-- completely unaudited direct-write bypass since Day 1: any ADMIN+
-- session could already PATCH businesses.tax_rate/currency/name/etc.
-- directly via REST with zero audit_logs row, identical in shape to the
-- sales_update/payments_update/business_members_update bypasses F9-2 and
-- F9-3 closed.
--
-- update_business_settings() replaces that policy as the sole mutation
-- path: SECURITY DEFINER, re-derives the caller's rank server-side via
-- has_role_at_least(p_business_id, 'ADMIN') (never trusts the client),
-- captures the pre-update row, performs the update, and inserts exactly
-- one SETTINGS_CHANGE audit_logs row in the same transaction -- a
-- rejected call (wrong rank, business not found, or a CHECK-constraint
-- violation such as an invalid currency length or an out-of-range
-- tax_rate, both already enforced at the column level since
-- 0002_businesses_branches.sql) raises before reaching the insert, so it
-- can never leave behind a row claiming success.
--
-- businesses_update is dropped once the RPC exists, exactly as
-- sales_update/payments_update/business_members_update were dropped in
-- their respective migrations -- confirmed unused by any other caller
-- first. businesses_select and every other policy on this table are
-- untouched.
--
-- Intended end state:
--   direct authenticated PATCH businesses -> DENIED for every role
--     (0 rows, RLS)
--   update_business_settings -> succeeds for ADMIN+, producing exactly
--     one SETTINGS_CHANGE audit_logs row in the same transaction
--   anon EXECUTE on the new function -> DENIED (42501)
create or replace function update_business_settings(
  p_business_id uuid,
  p_name text,
  p_phone text,
  p_email text,
  p_address text,
  p_currency text,
  p_tax_enabled boolean,
  p_tax_rate numeric,
  p_logo_url text
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business businesses;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'ADMIN') then
    raise exception 'Insufficient permission to change business settings';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Business name is required';
  end if;

  select * into v_business from businesses where id = p_business_id for update;

  if v_business.id is null then
    raise exception 'Business not found';
  end if;

  v_old_data := to_jsonb(v_business);

  update businesses set
    name = trim(p_name),
    phone = p_phone,
    email = p_email,
    address = p_address,
    currency = p_currency,
    tax_enabled = p_tax_enabled,
    tax_rate = p_tax_rate,
    logo_url = p_logo_url
    where id = p_business_id
    returning * into v_business;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'SETTINGS_CHANGE', 'business', v_business.id, v_old_data, to_jsonb(v_business));

  return v_business;
end;
$$;

revoke execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) from public;
revoke execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) from anon;
grant execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) to authenticated;

-- Confirmed unused by any repository (see header) -- close the direct-
-- write bypass now that the RPC covers its legitimate use.
drop policy businesses_update on businesses;

-- ===== 0029_complete_sale_authoritative_tax.sql =====
-- F9-6-1 (final security/release gap audit): complete_sale trusted
-- p_tax_amount verbatim from the client for both sales.tax_amount and
-- sales.total_amount, with only the table's own `tax_amount >= 0` CHECK
-- constraint (0007_sales.sql) as any guard. F7-1 (0024) already made
-- unit_price authoritative by resolving it server-side from the catalog,
-- but that treatment was never extended to tax, even though tax feeds
-- into total_amount exactly as directly as price does. A CASHIER+ caller
-- invoking complete_sale directly (not through the normal client, which
-- always computes tax correctly) could submit p_tax_amount = 0 on a
-- tax-enabled sale, or any other non-negative value, and have it accepted
-- unchecked -- corrupting recorded revenue/tax figures on every sale.
--
-- Fix: tax is now computed server-side from the target business's own
-- tax_enabled/tax_rate (0002_businesses_branches.sql), read fresh at sale
-- time via a plain `where id = p_business_id` lookup -- the same tenant
-- scoping already used throughout this function, never trusting any
-- other business identity. The rule mirrors CartState.taxAmount
-- (lib/features/pos/domain/cart_state.dart) exactly: zero unless
-- tax_enabled, tax_rate > 0, and the taxable base (subtotal - discount)
-- is positive; otherwise round(taxable_base * tax_rate / 100, 2), the
-- same round(numeric, 2) convention complete_sale already uses for
-- commission calculation.
--
-- p_tax_amount remains in the signature for wire compatibility with
-- PosRepository.completeSale (no reason to force a client change), but
-- its value is no longer read into v_total or sales.tax_amount at all --
-- verified by inspection that every remaining reference to it is gone
-- from the function body below.
--
-- Every other line is unchanged from 0024, verbatim: the auth.uid()/
-- has_role_at_least('CASHIER') guard, the idempotency short-circuit, the
-- customer tenant-validation check, Pass 1's authoritative catalog-price
-- resolution (F7-1) and per-item discount bound, Pass 2's item/inventory/
-- commission inserts, the mandatory-payment-covers-total check (F7-2,
-- now checked against the corrected total), the customer-stats trusted-
-- context update, and the single PAYMENT audit_logs insert (now simply
-- carrying the corrected tax_amount/total_amount in its new_data
-- snapshot -- no new audit row, no change to when or how it fires).
--
-- Intended end state:
--   tax-enabled business, forged p_tax_amount = 0 -> persisted tax_amount
--     is still the correct server-computed amount, not zero
--   tax-enabled business, forged inflated p_tax_amount -> persisted
--     tax_amount is still the correct server-computed amount
--   tax-disabled business, forged non-zero p_tax_amount -> persisted
--     tax_amount = 0
--   a paid_amount sufficient only for the forged (wrong) total is
--     rejected -- payment validation now runs against the authoritative
--     total, closing the actual transaction boundary, not just the
--     stored display value
create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_resolved_items jsonb := '[]'::jsonb;
  v_subtotal numeric(14,2) := 0;
  v_taxable_base numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_unit_price numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
  v_quantity integer;
  v_discount numeric(14,2);
  v_business businesses;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_business from businesses where id = p_business_id;

  -- Pass 1: resolve each item's authoritative catalog price exactly once
  -- (never the client-supplied unit_price) and accumulate the sale's
  -- subtotal from those authoritative values.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::int, 1);
    v_discount := coalesce((v_item->>'discount_amount')::numeric, 0);
    v_service_commission_type := null;
    v_service_commission_value := null;

    if (v_item->>'item_type') = 'SERVICE' then
      select price, commission_type, commission_value
        into v_unit_price, v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_unit_price is null then
        raise exception 'Service not found in this business';
      end if;
    elsif (v_item->>'item_type') = 'PRODUCT' then
      select selling_price into v_unit_price
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_unit_price is null then
        raise exception 'Product not found in this business';
      end if;
    else
      raise exception 'Invalid item type';
    end if;

    v_item_subtotal := (v_unit_price * v_quantity) - v_discount;
    if v_item_subtotal < 0 then
      raise exception 'Discount cannot exceed the item subtotal';
    end if;

    v_subtotal := v_subtotal + v_item_subtotal;

    v_resolved_items := v_resolved_items || jsonb_build_object(
      'item_type', v_item->>'item_type',
      'service_id', nullif(v_item->>'service_id', ''),
      'product_id', nullif(v_item->>'product_id', ''),
      'staff_id', v_item->>'staff_id',
      'name_snapshot', v_item->>'name_snapshot',
      'quantity', v_quantity,
      'unit_price', v_unit_price,
      'discount_amount', v_discount,
      'item_subtotal', v_item_subtotal,
      'commission_type', v_service_commission_type,
      'commission_value', v_service_commission_value
    );
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  -- F9-6-1: tax is now derived authoritatively from the business's own
  -- configuration, never from the client-supplied p_tax_amount (kept in
  -- the signature only for wire compatibility -- unused below).
  v_taxable_base := v_subtotal - coalesce(p_discount_amount, 0);

  if v_business.tax_enabled and v_business.tax_rate > 0 and v_taxable_base > 0 then
    v_tax := round(v_taxable_base * v_business.tax_rate / 100, 2);
  else
    v_tax := 0;
  end if;

  v_total := v_taxable_base + v_tax;
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount < v_total then
    raise exception 'Payment amount cannot be less than the sale total';
  end if;

  v_payment_status := 'COMPLETED';
  v_change := p_paid_amount - v_total;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), v_tax, v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  -- Pass 2: persist each line using the already-resolved authoritative
  -- price/subtotal from pass 1 -- no re-query of services/products for
  -- price. Stock sufficiency is still checked and deducted here, in the
  -- same order as before the fix, so two lines referencing the same
  -- product still interact correctly (the lock was already taken in
  -- pass 1, so this re-read is immediate, not blocking).
  for v_item in select * from jsonb_array_elements(v_resolved_items)
  loop
    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    v_commission_amount := 0;
    if (v_item->>'item_type') = 'SERVICE' and v_staff_valid and (v_item->>'commission_type') is not null then
      if (v_item->>'commission_type') = 'PERCENTAGE' then
        v_commission_amount := round(
          (v_item->>'item_subtotal')::numeric * coalesce((v_item->>'commission_value')::numeric, 0) / 100, 2
        );
      else
        v_commission_amount := coalesce((v_item->>'commission_value')::numeric, 0);
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric, (v_item->>'discount_amount')::numeric,
      (v_item->>'item_subtotal')::numeric, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid
        for update;

      if v_product_stock < (v_item->>'quantity')::int then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      update products set stock_quantity = stock_quantity - (v_item->>'quantity')::int
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -(v_item->>'quantity')::int, 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        (v_item->>'commission_type')::commission_kind, coalesce((v_item->>'commission_value')::numeric, 0),
        v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, v_payment_status, auth.uid());

  if p_customer_id is not null then
    perform set_config('app.trusted_customer_stats_update', 'true', true);
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

-- CREATE OR REPLACE preserves the existing GRANT/REVOKE state set by 0021
-- (same signature, so no privilege reset occurs); restated here for
-- clarity and to be self-contained regardless of migration-application
-- order. anon/public EXECUTE remain revoked; only authenticated retains
-- access.
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- ===== 0030_appointments_schema.sql =====
-- Phase 1: Appointment / Calendar.
--
-- Following the pattern complete_sale/adjust_stock/set_member_role already
-- established (and business_members after 0027, which dropped its direct
-- UPDATE policy once its RPCs existed): validated, audited writes go
-- through a SECURITY DEFINER RPC, never a raw client INSERT/UPDATE. So
-- appointments/appointment_items get a SELECT-only RLS policy here; the
-- RPCs in 0031_appointment_rpcs.sql are the only write path.
--
-- One appointment = one staff member, one time block (start_at/end_at),
-- protected against double-booking by a GIST exclusion constraint -- this
-- is enforced by Postgres itself, not application logic, so it holds even
-- under concurrent bookings. An appointment can carry multiple services
-- (appointment_items), each optionally attributed to a different staff
-- member for commission purposes (mirrors sale_items.staff_id), but only
-- the appointment's own staff_id/time range is conflict-checked -- keeping
-- the concurrency-safety story to one exclusion constraint with one clear
-- owner of the booked slot.

create extension if not exists btree_gist;

create type appointment_status as enum (
  'SCHEDULED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
);

create table appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  customer_id uuid references customers(id) on delete set null,
  staff_id uuid not null references profiles(id) on delete restrict,
  start_at timestamptz not null,
  end_at timestamptz not null check (end_at > start_at),
  status appointment_status not null default 'SCHEDULED',
  notes text,
  cancel_reason text,
  sale_id uuid references sales(id) on delete set null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointments_no_staff_overlap exclude using gist (
    staff_id with =,
    tstzrange(start_at, end_at) with &&
  ) where (status in ('SCHEDULED', 'CONFIRMED', 'CHECKED_IN'))
);

create index appointments_business_id_idx on appointments(business_id, start_at);
create index appointments_staff_id_idx on appointments(staff_id, start_at);
create index appointments_customer_id_idx on appointments(customer_id);
create index appointments_branch_id_idx on appointments(branch_id);
create index appointments_status_idx on appointments(business_id, status);

create trigger appointments_set_updated_at
  before update on appointments
  for each row execute function set_updated_at();

create table appointment_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  appointment_id uuid not null references appointments(id) on delete cascade,
  service_id uuid not null references services(id) on delete restrict,
  staff_id uuid references profiles(id) on delete set null,
  name_snapshot text not null,
  duration_minutes integer not null check (duration_minutes > 0),
  price_snapshot numeric(14,2) not null check (price_snapshot >= 0),
  created_at timestamptz not null default now()
);

create index appointment_items_appointment_id_idx on appointment_items(appointment_id);
create index appointment_items_business_id_idx on appointment_items(business_id);
create index appointment_items_service_id_idx on appointment_items(service_id);

alter table appointments enable row level security;
alter table appointment_items enable row level security;

-- SELECT only -- see header. Insert/update happen exclusively through
-- book_appointment/set_appointment_status/reschedule_appointment.

create policy appointments_select on appointments
  for select using (is_member(business_id));

create policy appointment_items_select on appointment_items
  for select using (is_member(business_id));

-- ===== 0031_appointment_rpcs.sql =====
-- Phase 1: Appointment / Calendar -- write-path RPCs. See
-- 0030_appointments_schema.sql for why appointments/appointment_items have
-- no direct-write RLS policy: these three functions are the only way to
-- create, reschedule, or transition an appointment, exactly like
-- complete_sale/adjust_stock/set_member_role for their own tables.
--
-- All three re-derive the caller's role via has_role_at_least() themselves
-- (never trust p_business_id alone), validate staff_id/customer_id/
-- branch_id/service_id belong to p_business_id (the same style of check
-- complete_sale uses for staff_id/customer_id/service_id/product_id), and
-- rely on appointments_no_staff_overlap (the GIST exclusion constraint) to
-- reject double-bookings -- caught here only to turn a raw
-- "exclusion_violation" Postgres error into a readable message.

create or replace function book_appointment(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_items jsonb,
  p_notes text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_item jsonb;
  v_service_id uuid;
  v_item_staff_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to book an appointment';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'An appointment must have at least one service';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from branches where id = p_branch_id and business_id = p_business_id
  ) then
    raise exception 'Branch not found in this business';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_service_id := nullif(v_item->>'service_id', '')::uuid;
    if v_service_id is null or not exists (
      select 1 from services where id = v_service_id and business_id = p_business_id
    ) then
      raise exception 'Service not found in this business';
    end if;

    v_item_staff_id := nullif(v_item->>'staff_id', '')::uuid;
    if v_item_staff_id is not null and not exists (
      select 1 from business_members
      where business_id = p_business_id and user_id = v_item_staff_id and active = true
    ) then
      raise exception 'Item staff member is not an active member of this business';
    end if;
  end loop;

  begin
    insert into appointments (
      business_id, branch_id, customer_id, staff_id, start_at, end_at, notes, created_by
    ) values (
      p_business_id, p_branch_id, p_customer_id, p_staff_id, p_start_at, p_end_at, p_notes, auth.uid()
    ) returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into appointment_items (
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes, price_snapshot
    ) values (
      p_business_id, v_appointment.id,
      nullif(v_item->>'service_id', '')::uuid,
      nullif(v_item->>'staff_id', '')::uuid,
      v_item->>'name_snapshot',
      coalesce((v_item->>'duration_minutes')::int, 30),
      coalesce((v_item->>'price_snapshot')::numeric, 0)
    );
  end loop;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'appointment', v_appointment.id, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from public;
revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from anon;
grant execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) to authenticated;

-- Status state machine:
--   SCHEDULED  -> CONFIRMED, CANCELLED, NO_SHOW
--   CONFIRMED  -> CHECKED_IN, CANCELLED, NO_SHOW
--   CHECKED_IN -> COMPLETED, CANCELLED
--   COMPLETED / CANCELLED / NO_SHOW -> terminal, no further transitions

create or replace function set_appointment_status(
  p_business_id uuid,
  p_appointment_id uuid,
  p_status appointment_status,
  p_cancel_reason text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
  v_allowed appointment_status[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to change appointment status';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  v_allowed := case v_appointment.status
    when 'SCHEDULED' then array['CONFIRMED', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CONFIRMED' then array['CHECKED_IN', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CHECKED_IN' then array['COMPLETED', 'CANCELLED']::appointment_status[]
    else array[]::appointment_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move an appointment from % to %', v_appointment.status, p_status;
  end if;

  v_old_data := to_jsonb(v_appointment);

  update appointments set
    status = p_status,
    cancel_reason = case when p_status = 'CANCELLED' then p_cancel_reason else cancel_reason end
  where id = p_appointment_id
  returning * into v_appointment;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;

-- Reschedule: only while the appointment is still SCHEDULED/CONFIRMED --
-- once a customer has checked in, moving the time no longer makes sense
-- and should be a cancel + rebook instead.

create or replace function reschedule_appointment(
  p_business_id uuid,
  p_appointment_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to reschedule an appointment';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  if v_appointment.status not in ('SCHEDULED', 'CONFIRMED') then
    raise exception 'Only a scheduled or confirmed appointment can be rescheduled';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  v_old_data := to_jsonb(v_appointment);

  begin
    update appointments set
      staff_id = p_staff_id,
      start_at = p_start_at,
      end_at = p_end_at
    where id = p_appointment_id
    returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) from public;
revoke execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) from anon;
grant execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) to authenticated;
commit;

begin;

-- ===== 0032_packages_schema.sql =====
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

-- ===== 0033_appointment_items_package_link.sql =====
-- Phase 2: lets a booked appointment_item declare, up front, which
-- customer_package_item it's meant to be covered by. Nullable and purely
-- additive -- every existing Phase 1 row/RPC call is unaffected (defaults
-- null). The actual session redemption still only happens at completion
-- (0036_package_rpcs.sql extends set_appointment_status), never at
-- booking -- this column only records intent, so it must not be trusted as
-- proof of redemption on its own.

alter table appointment_items
  add column customer_package_item_id uuid references customer_package_items(id) on delete set null;

create index appointment_items_customer_package_item_id_idx
  on appointment_items(customer_package_item_id)
  where customer_package_item_id is not null;

commit;

begin;

-- ===== 0034_sale_item_kind_package_value.sql =====
-- Phase 2: adds the PACKAGE value to sale_item_kind.
--
-- This is deliberately its OWN migration, containing nothing else.
-- PostgreSQL does not allow a newly added enum value to be used (compared,
-- cast from a literal, etc.) within the same transaction that added it --
-- and a multi-statement SQL Editor paste runs as a single implicit
-- transaction. 0035_sale_items_package_column.sql (which needs to write
-- `item_type = 'PACKAGE'` into a CHECK constraint) must therefore be
-- applied as a separate paste/transaction, after this one has committed.
alter type sale_item_kind add value 'PACKAGE';

commit;

begin;

-- ===== 0035_sale_items_package_column.sql =====
-- Phase 2: sale_items gains a PACKAGE line-item shape, one row per package
-- purchase (created by purchase_package, 0037_package_rpcs.sql). Applied
-- after 0034 has committed the PACKAGE enum value -- see that file's header
-- for why this must be a separate transaction.
--
-- package_id is nullable and `on delete set null`, same treatment as
-- customer_packages.package_id (0032): the sale_items row already carries
-- its own name_snapshot/unit_price, so it stays fully meaningful even if
-- the package definition is later deleted.

alter table sale_items
  add column package_id uuid references packages(id) on delete set null;

create index sale_items_package_id_idx on sale_items(package_id);

alter table sale_items drop constraint sale_items_item_reference_chk;

alter table sale_items add constraint sale_items_item_reference_chk check (
  (item_type = 'SERVICE' and service_id is not null and product_id is null and package_id is null) or
  (item_type = 'PRODUCT' and product_id is not null and service_id is null and package_id is null) or
  (item_type = 'PACKAGE' and package_id is not null and service_id is null and product_id is null)
);

-- ===== 0036_commissions_redemption_source.sql =====
-- Phase 2: lets a commission originate from a package-session redemption
-- instead of a sale_item -- approved design (see Phase 2 architecture
-- review): commission is earned by whoever performs the redeemed service,
-- not at package purchase time, so redemption-driven commissions have no
-- sale/sale_item at all.
--
-- sale_id and sale_item_id both become nullable; the new CHECK constraint
-- enforces the two allowed shapes exactly (never a commission with neither
-- source, or with both):
--   sale-driven:      sale_id NOT NULL, sale_item_id NOT NULL, redemption NULL
--   redemption-driven: sale_id NULL,     sale_item_id NULL,     redemption NOT NULL
--
-- customer_package_redemption_id uses ON DELETE RESTRICT (not CASCADE):
-- redemptions are financial/attribution history and must never silently
-- disappear out from under a commission row, the same reasoning already
-- applied to sales.cashier_id/payments.created_by/appointments.staff_id
-- (all `on delete restrict`) elsewhere in this schema.
--
-- No existing repository, screen, or report query is touched here --
-- CommissionRepository.updateStatus only ever writes `status`, and
-- reports_repository's commission query only selects commission_amount;
-- neither depends on sale_id/sale_item_id shape. The one real Flutter
-- dependency (Commission.fromJson's non-nullable saleId/saleItemId casts)
-- is fixed in the same Phase 2 change set, not here.

alter table commissions alter column sale_id drop not null;
alter table commissions alter column sale_item_id drop not null;

alter table commissions
  add column customer_package_redemption_id uuid references customer_package_redemptions(id) on delete restrict;

create unique index commissions_redemption_unique on commissions(customer_package_redemption_id)
  where customer_package_redemption_id is not null;

alter table commissions add constraint commissions_source_chk check (
  (sale_id is not null and sale_item_id is not null and customer_package_redemption_id is null)
  or
  (sale_id is null and sale_item_id is null and customer_package_redemption_id is not null)
);

-- ===== 0037_package_rpcs.sql =====
-- Phase 2: purchase_package (new) and set_appointment_status (extended).
--
-- purchase_package follows complete_sale's exact proven shape: auth.uid()
-- guard, has_role_at_least(p_business_id, 'CASHIER'), idempotency
-- short-circuit, tenant-scoped lookups for every referenced id, and
-- server-authoritative pricing -- packages.price is read here and used for
-- every downstream calculation; the client never supplies a price. Tax is
-- derived the same way 0029 fixed complete_sale to derive it (from the
-- business's own tax_enabled/tax_rate, never a client-supplied amount) --
-- there is no legacy p_tax_amount parameter to keep for wire compatibility
-- since this RPC is new. A customer is required (not optional, unlike
-- complete_sale) per the approved UX requirement that package purchases
-- always have an owner.
--
-- No sale_items.staff_id/commission on the PACKAGE line -- approved
-- design: no service-performance commission is earned merely by selling a
-- package (see 0036's header). Commission is created only at redemption,
-- inside set_appointment_status below.
create or replace function purchase_package(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_package_id uuid,
  p_discount_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns customer_packages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_package packages;
  v_customer_package customer_packages;
  v_existing_sale sales;
  v_sale sales;
  v_business businesses;
  v_item record;
  v_subtotal numeric(14,2);
  v_taxable_base numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to purchase a package';
  end if;

  if p_customer_id is null then
    raise exception 'A customer is required to purchase a package';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing_sale from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_customer_package from customer_packages where sale_id = v_existing_sale.id;
    return v_customer_package;
  end if;

  if not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_package from packages
    where id = p_package_id and business_id = p_business_id and active = true;

  if v_package.id is null then
    raise exception 'Package not found or inactive in this business';
  end if;

  if not exists (select 1 from package_items where package_id = p_package_id) then
    raise exception 'Package has no included services';
  end if;

  select * into v_business from businesses where id = p_business_id;

  v_subtotal := v_package.price;
  v_taxable_base := v_subtotal - coalesce(p_discount_amount, 0);
  if v_taxable_base < 0 then
    raise exception 'Discount cannot exceed the package price';
  end if;

  if v_business.tax_enabled and v_business.tax_rate > 0 and v_taxable_base > 0 then
    v_tax := round(v_taxable_base * v_business.tax_rate / 100, 2);
  else
    v_tax := 0;
  end if;

  v_total := v_taxable_base + v_tax;

  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount < v_total then
    raise exception 'Payment amount cannot be less than the package total';
  end if;

  v_payment_status := 'COMPLETED';
  v_change := p_paid_amount - v_total;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), v_tax, v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  insert into sale_items (
    business_id, sale_id, item_type, package_id,
    name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
  ) values (
    p_business_id, v_sale.id, 'PACKAGE', p_package_id,
    v_package.name, 1, v_package.price, coalesce(p_discount_amount, 0), v_taxable_base, 0
  );

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, v_payment_status, auth.uid());

  insert into customer_packages (
    business_id, customer_id, package_id, sale_id, name_snapshot, price_paid_snapshot, expires_at, status
  ) values (
    p_business_id, p_customer_id, p_package_id, v_sale.id, v_package.name, v_total,
    case when v_package.validity_days is not null then now() + (v_package.validity_days || ' days')::interval else null end,
    'ACTIVE'
  ) returning * into v_customer_package;

  for v_item in select * from package_items where package_id = p_package_id
  loop
    insert into customer_package_items (
      business_id, customer_package_id, service_id, name_snapshot, total_sessions, used_sessions
    )
    select p_business_id, v_customer_package.id, v_item.service_id, s.name, v_item.session_count, 0
    from services s where s.id = v_item.service_id;
  end loop;

  perform set_config('app.trusted_customer_stats_update', 'true', true);
  update customers set
    total_spent = total_spent + v_total,
    visit_count = visit_count + 1,
    last_visit_at = now()
  where id = p_customer_id and business_id = p_business_id;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'customer_package', v_customer_package.id, to_jsonb(v_customer_package));

  return v_customer_package;
end;
$$;

revoke execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) to authenticated;

-- set_appointment_status: every line above the "-- Phase 2:" marker below
-- is verbatim from 0031_appointment_rpcs.sql -- same signature, same
-- guards, same state machine, same original audit_logs insert. The only
-- change is the new block appended before RETURN, which only executes when
-- p_status = 'COMPLETED' and only touches appointment_items that were
-- explicitly linked to a package entitlement at booking time
-- (customer_package_item_id is not null) -- every other transition, and
-- every appointment with no package-linked items, is byte-for-byte
-- unchanged from Phase 1.
--
-- Redemption re-validates everything server-side at completion time (never
-- trusting that booking-time eligibility still holds): the entitlement's
-- customer must match the appointment's customer (the cross-check flagged
-- in the Phase 2 audit as the one risk with no existing precedent to copy),
-- its service must match the booked service, the package must still be
-- ACTIVE and not expired, and it must have a remaining session -- each
-- customer_package_items row is locked FOR UPDATE before any of this is
-- checked, so two appointments racing for the same entitlement's last
-- session resolve to exactly one success (the second blocks on the lock,
-- then observes used_sessions = total_sessions once it resumes and
-- raises). The partial unique index from 0032 is the second, DB-level
-- layer against double redemption, not the only one.
--
-- Commission is created only here, at redemption, per the approved design
-- (0036) -- never at package purchase. Staff validity is re-checked against
-- business_members at redemption time, the same defensive re-check
-- complete_sale already performs for its own commission attribution.
create or replace function set_appointment_status(
  p_business_id uuid,
  p_appointment_id uuid,
  p_status appointment_status,
  p_cancel_reason text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
  v_allowed appointment_status[];
  v_appt_item appointment_items;
  v_cpi customer_package_items;
  v_cp customer_packages;
  v_redemption customer_package_redemptions;
  v_staff_id uuid;
  v_staff_valid boolean;
  v_commission_type commission_kind;
  v_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to change appointment status';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  v_allowed := case v_appointment.status
    when 'SCHEDULED' then array['CONFIRMED', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CONFIRMED' then array['CHECKED_IN', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CHECKED_IN' then array['COMPLETED', 'CANCELLED']::appointment_status[]
    else array[]::appointment_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move an appointment from % to %', v_appointment.status, p_status;
  end if;

  v_old_data := to_jsonb(v_appointment);

  update appointments set
    status = p_status,
    cancel_reason = case when p_status = 'CANCELLED' then p_cancel_reason else cancel_reason end
  where id = p_appointment_id
  returning * into v_appointment;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  -- Phase 2: completion-time package redemption.
  if p_status = 'COMPLETED' then
    for v_appt_item in
      select * from appointment_items
      where appointment_id = p_appointment_id and customer_package_item_id is not null
    loop
      select * into v_cpi from customer_package_items
        where id = v_appt_item.customer_package_item_id and business_id = p_business_id
        for update;

      if v_cpi.id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      select * into v_cp from customer_packages where id = v_cpi.customer_package_id;

      if v_cp.customer_id is distinct from v_appointment.customer_id then
        raise exception 'This package entitlement does not belong to the appointment''s customer';
      end if;

      if v_cpi.service_id is distinct from v_appt_item.service_id then
        raise exception 'This package entitlement does not cover the booked service';
      end if;

      if v_cp.status <> 'ACTIVE' then
        raise exception 'This package is not active';
      end if;

      if v_cp.expires_at is not null and v_cp.expires_at < now() then
        raise exception 'This package has expired';
      end if;

      if v_cpi.used_sessions >= v_cpi.total_sessions then
        raise exception 'No remaining sessions on this package entitlement';
      end if;

      if exists (
        select 1 from customer_package_redemptions
        where appointment_item_id = v_appt_item.id and not reversed
      ) then
        raise exception 'This service has already been redeemed against a package';
      end if;

      update customer_package_items set used_sessions = used_sessions + 1
        where id = v_cpi.id
        returning * into v_cpi;

      v_staff_id := coalesce(v_appt_item.staff_id, v_appointment.staff_id);

      insert into customer_package_redemptions (
        business_id, customer_package_item_id, appointment_id, appointment_item_id, staff_id
      ) values (
        p_business_id, v_cpi.id, p_appointment_id, v_appt_item.id, v_staff_id
      ) returning * into v_redemption;

      insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
      values (p_business_id, auth.uid(), 'CREATE', 'customer_package_redemption', v_redemption.id, to_jsonb(v_redemption));

      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id and user_id = v_staff_id and active = true
      );

      select commission_type, commission_value into v_commission_type, v_commission_value
        from services where id = v_appt_item.service_id and business_id = p_business_id;

      v_commission_amount := 0;
      if v_staff_valid and v_commission_type is not null then
        if v_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_appt_item.price_snapshot * coalesce(v_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_commission_value, 0);
        end if;
      end if;

      if v_commission_amount > 0 then
        insert into commissions (
          business_id, customer_package_redemption_id, staff_id, commission_type,
          commission_rate, commission_amount, status
        ) values (
          p_business_id, v_redemption.id, v_staff_id,
          v_commission_type, coalesce(v_commission_value, 0), v_commission_amount, 'PENDING'
        );
      end if;
    end loop;
  end if;

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;

-- ===== 0038_void_sale_package_guard.sql =====
-- Phase 2: extends void_sale with the approved package-void policy --
-- every line below the "-- Phase 2:" marker inside the function body is
-- new; every other line (auth guard, role floor, reason requirement, sale
-- lookup/lock, inventory reversal, commission reversal, sales/payments
-- update, audit insert) is verbatim from 0026_void_sale.sql.
--
-- Policy: a package sale with zero redeemed sessions may still be voided
-- (and its customer_packages row is cancelled as part of the same
-- transaction); a package sale with ANY redeemed session is rejected
-- outright -- no partial reversal, no partial-refund semantics invented.
-- The check runs immediately after the sale is located/locked and before
-- any reversal side effect begins, so a rejected void leaves absolutely
-- nothing touched (same all-or-nothing shape the rest of this function
-- already has). A non-package sale is entirely unaffected: the new lookup
-- simply finds no customer_packages row and both new blocks no-op.
create or replace function void_sale(
  p_business_id uuid,
  p_sale_id uuid,
  p_reason text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_old_sale jsonb;
  v_item record;
  v_product products;
  v_reversed_commission_count int := 0;
  v_reversed_inventory_count int := 0;
  v_skipped_product_deleted_count int := 0;
  v_customer_package customer_packages;
  v_has_redemptions boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to void a sale';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A void reason is required';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Only a completed sale can be voided';
  end if;

  v_old_sale := to_jsonb(v_sale);

  -- Phase 2: reject outright if this sale's package has any redeemed
  -- session -- checked before any reversal side effect begins.
  select * into v_customer_package from customer_packages where sale_id = p_sale_id;

  if v_customer_package.id is not null then
    select exists (
      select 1 from customer_package_items
      where customer_package_id = v_customer_package.id and used_sessions > 0
    ) into v_has_redemptions;

    if v_has_redemptions then
      raise exception 'Cannot void a package sale that has redeemed sessions';
    end if;
  end if;

  for v_item in
    select * from sale_items where sale_id = p_sale_id and item_type = 'PRODUCT'
  loop
    if v_item.product_id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    select * into v_product from products
      where id = v_item.product_id and business_id = p_business_id
      for update;

    if v_product.id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    update products set stock_quantity = stock_quantity + v_item.quantity
      where id = v_item.product_id;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, reference_id, note, created_by
    ) values (
      p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_item.quantity,
      'sale_void', p_sale_id, 'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
    );

    v_reversed_inventory_count := v_reversed_inventory_count + 1;
  end loop;

  update commissions set status = 'REVERSED'
    where sale_id = p_sale_id and status <> 'REVERSED';
  get diagnostics v_reversed_commission_count = row_count;

  update sales set
    status = 'VOIDED',
    void_reason = p_reason,
    voided_by = auth.uid(),
    voided_at = now()
    where id = p_sale_id
    returning * into v_sale;

  update payments set status = 'REFUNDED'
    where sale_id = p_sale_id and status <> 'REFUNDED';

  -- Phase 2: cancel the (unused) package entitlement alongside the sale.
  if v_customer_package.id is not null then
    update customer_packages set status = 'CANCELLED' where id = v_customer_package.id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'VOID', 'sale', p_sale_id, v_old_sale, to_jsonb(v_sale),
    jsonb_build_object(
      'reason', p_reason,
      'reversed_commission_count', v_reversed_commission_count,
      'reversed_inventory_line_count', v_reversed_inventory_count,
      'skipped_product_deleted_lines', v_skipped_product_deleted_count,
      'package_cancelled', v_customer_package.id is not null
    )
  );

  return v_sale;
end;
$$;

revoke execute on function void_sale(uuid, uuid, text) from public;
revoke execute on function void_sale(uuid, uuid, text) from anon;
grant execute on function void_sale(uuid, uuid, text) to authenticated;

commit;

begin;

-- ===== 0039_book_appointment_package_link.sql =====
-- Phase 2: book_appointment learns to persist an optional
-- customer_package_item_id per item (0033's new appointment_items column).
-- This does NOT change the function's signature -- p_items is still the
-- same jsonb parameter; unrecognized/absent keys were already ignored, so
-- every existing caller that doesn't send this field is unaffected.
--
-- Booking-time validation here (entitlement belongs to the business, its
-- owning customer_package.customer_id matches p_customer_id, its
-- service_id matches the item's service_id) is a UX nicety only -- it lets
-- an invalid selection be rejected immediately instead of at completion.
-- It is NOT a substitute for the redemption-time re-validation
-- set_appointment_status performs (0037): status/expiry/remaining-sessions
-- can all change between booking and completion, so nothing here is
-- treated as proof that a session may actually be consumed later.
--
-- Every other line is verbatim from 0031_appointment_rpcs.sql.
create or replace function book_appointment(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_items jsonb,
  p_notes text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_item jsonb;
  v_service_id uuid;
  v_item_staff_id uuid;
  v_customer_package_item_id uuid;
  v_cpi_customer_id uuid;
  v_cpi_service_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to book an appointment';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'An appointment must have at least one service';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from branches where id = p_branch_id and business_id = p_business_id
  ) then
    raise exception 'Branch not found in this business';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_service_id := nullif(v_item->>'service_id', '')::uuid;
    if v_service_id is null or not exists (
      select 1 from services where id = v_service_id and business_id = p_business_id
    ) then
      raise exception 'Service not found in this business';
    end if;

    v_item_staff_id := nullif(v_item->>'staff_id', '')::uuid;
    if v_item_staff_id is not null and not exists (
      select 1 from business_members
      where business_id = p_business_id and user_id = v_item_staff_id and active = true
    ) then
      raise exception 'Item staff member is not an active member of this business';
    end if;

    -- Phase 2: optional entitlement link, validated at booking time only
    -- as a UX nicety -- see header.
    v_customer_package_item_id := nullif(v_item->>'customer_package_item_id', '')::uuid;
    if v_customer_package_item_id is not null then
      select cp.customer_id, cpi.service_id into v_cpi_customer_id, v_cpi_service_id
        from customer_package_items cpi
        join customer_packages cp on cp.id = cpi.customer_package_id
        where cpi.id = v_customer_package_item_id and cpi.business_id = p_business_id;

      if v_cpi_customer_id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      if p_customer_id is null or v_cpi_customer_id <> p_customer_id then
        raise exception 'This package entitlement does not belong to the selected customer';
      end if;

      if v_cpi_service_id is distinct from v_service_id then
        raise exception 'This package entitlement does not cover the selected service';
      end if;
    end if;
  end loop;

  begin
    insert into appointments (
      business_id, branch_id, customer_id, staff_id, start_at, end_at, notes, created_by
    ) values (
      p_business_id, p_branch_id, p_customer_id, p_staff_id, p_start_at, p_end_at, p_notes, auth.uid()
    ) returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into appointment_items (
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes,
      price_snapshot, customer_package_item_id
    ) values (
      p_business_id, v_appointment.id,
      nullif(v_item->>'service_id', '')::uuid,
      nullif(v_item->>'staff_id', '')::uuid,
      v_item->>'name_snapshot',
      coalesce((v_item->>'duration_minutes')::int, 30),
      coalesce((v_item->>'price_snapshot')::numeric, 0),
      nullif(v_item->>'customer_package_item_id', '')::uuid
    );
  end loop;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'appointment', v_appointment.id, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from public;
revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from anon;
grant execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) to authenticated;
commit;

begin;

-- ===== 0040_sale_items_package_fk_restrict.sql =====
-- Phase 2 forensic fix: sale_items.package_id was added in
-- 0035_sale_items_package_column.sql as an inline column reference with no
-- explicit constraint name, so Postgres auto-named it
-- sale_items_package_id_fkey (confirmed by inspection, not assumed) --
-- `on delete set null`.
--
-- Defect (confirmed live during Phase 2 E2E regression): deleting a
-- `packages` row that has ever been purchased cascades that SET NULL onto
-- its sale_items row, which then immediately violates
-- sale_items_item_reference_chk (0035) -- that constraint requires
-- package_id IS NOT NULL whenever item_type = 'PACKAGE'. The DELETE fails
-- with a confusing 23514 check_violation instead of a clear, standard
-- foreign-key rejection.
--
-- Fix: package_id becomes `on delete restrict`, matching every other FK in
-- this schema that backs financial/attribution history a row must never
-- silently lose (sales.cashier_id, payments.created_by,
-- appointments.staff_id, customer_packages.customer_id,
-- customer_package_redemptions.customer_package_item_id -- all already
-- `on delete restrict` for the same reason). This does not change behavior
-- for any existing row: it only affects a future DELETE attempt against a
-- packages row that already has purchase history, which now fails
-- immediately and cleanly (23503 foreign_key_violation) instead of via the
-- CHECK constraint. A never-purchased package is completely unaffected --
-- RESTRICT only blocks deletion when a referencing sale_items row exists.
--
-- Nothing else changes: sale_items_item_reference_chk, the services/
-- products FKs (which have the identical latent SET NULL + CHECK pattern,
-- confirmed by inspection but explicitly out of scope for this migration
-- per the approved fix), package RLS, and every Phase 2 RPC are untouched.
-- No data migration is required -- every existing package_id value is
-- already valid against packages(id) (it could not have violated the prior
-- constraint), so validating the new constraint is instant.
alter table sale_items
  drop constraint sale_items_package_id_fkey;

alter table sale_items
  add constraint sale_items_package_id_fkey
  foreign key (package_id)
  references packages(id)
  on delete restrict;
commit;

begin;
-- P1-01 fix: book_appointment previously persisted appointment_items.
-- name_snapshot/price_snapshot verbatim from client-supplied p_items, with
-- no re-derivation from services -- the same class of bug F7-1
-- (0024_complete_sale_price_and_payment_integrity.sql) already fixed for
-- complete_sale's unit_price. Phase 2's set_appointment_status (0037) then
-- uses appointment_items.price_snapshot for PERCENTAGE commission
-- calculation on package-redeemed sessions, so an unpatched client-supplied
-- price was directly exploitable for commission manipulation.
--
-- Fix: the second loop (the one that inserts appointment_items) now looks
-- up the service row by the already-validated service_id and writes
-- services.name / services.price as name_snapshot / price_snapshot. The
-- client-supplied 'name_snapshot' and 'price_snapshot' keys in p_items are
-- no longer read at all for these two columns. duration_minutes is
-- untouched (out of P1-01's scope -- not a finding, not a financial value).
--
-- Every other line is verbatim from 0039_book_appointment_package_link.sql:
-- auth guard, role check, staff/customer/branch/service/package-entitlement
-- validation, the double-booking exclusion-violation handler, and the
-- audit_logs insert are all unchanged.
create or replace function book_appointment(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_items jsonb,
  p_notes text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_item jsonb;
  v_service_id uuid;
  v_item_staff_id uuid;
  v_customer_package_item_id uuid;
  v_cpi_customer_id uuid;
  v_cpi_service_id uuid;
  v_service services;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to book an appointment';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'An appointment must have at least one service';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from branches where id = p_branch_id and business_id = p_business_id
  ) then
    raise exception 'Branch not found in this business';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_service_id := nullif(v_item->>'service_id', '')::uuid;
    if v_service_id is null or not exists (
      select 1 from services where id = v_service_id and business_id = p_business_id
    ) then
      raise exception 'Service not found in this business';
    end if;

    v_item_staff_id := nullif(v_item->>'staff_id', '')::uuid;
    if v_item_staff_id is not null and not exists (
      select 1 from business_members
      where business_id = p_business_id and user_id = v_item_staff_id and active = true
    ) then
      raise exception 'Item staff member is not an active member of this business';
    end if;

    -- Phase 2: optional entitlement link, validated at booking time only
    -- as a UX nicety -- see 0039's header.
    v_customer_package_item_id := nullif(v_item->>'customer_package_item_id', '')::uuid;
    if v_customer_package_item_id is not null then
      select cp.customer_id, cpi.service_id into v_cpi_customer_id, v_cpi_service_id
        from customer_package_items cpi
        join customer_packages cp on cp.id = cpi.customer_package_id
        where cpi.id = v_customer_package_item_id and cpi.business_id = p_business_id;

      if v_cpi_customer_id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      if p_customer_id is null or v_cpi_customer_id <> p_customer_id then
        raise exception 'This package entitlement does not belong to the selected customer';
      end if;

      if v_cpi_service_id is distinct from v_service_id then
        raise exception 'This package entitlement does not cover the selected service';
      end if;
    end if;
  end loop;

  begin
    insert into appointments (
      business_id, branch_id, customer_id, staff_id, start_at, end_at, notes, created_by
    ) values (
      p_business_id, p_branch_id, p_customer_id, p_staff_id, p_start_at, p_end_at, p_notes, auth.uid()
    ) returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    -- P1-01 fix: name_snapshot/price_snapshot are derived here from the
    -- services table (already validated above to belong to p_business_id),
    -- never from v_item->>'name_snapshot' / v_item->>'price_snapshot'.
    select * into v_service from services
      where id = nullif(v_item->>'service_id', '')::uuid and business_id = p_business_id;

    insert into appointment_items (
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes,
      price_snapshot, customer_package_item_id
    ) values (
      p_business_id, v_appointment.id,
      v_service.id,
      nullif(v_item->>'staff_id', '')::uuid,
      v_service.name,
      coalesce((v_item->>'duration_minutes')::int, 30),
      v_service.price,
      nullif(v_item->>'customer_package_item_id', '')::uuid
    );
  end loop;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'appointment', v_appointment.id, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from public;
revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from anon;
grant execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) to authenticated;
commit;

begin;
-- Phase 3 (Deposit / Outstanding Balance): adds the PARTIAL value to
-- payment_status_enum, used by both sales.payment_status (a sale that has
-- received some but not all of its total) and, transitively, nowhere else
-- (payments.status for an individual payment row is always COMPLETED or
-- REFUNDED -- an individual payment transaction is never itself "partial",
-- only the sale's aggregate settlement state is).
--
-- Standalone file/transaction, following the exact precedent established by
-- 0034_sale_item_kind_package_value.sql: Postgres cannot use a newly added
-- enum value inside the same transaction that added it, so this migration
-- does nothing else. The functions that reference 'PARTIAL' (complete_sale,
-- record_sale_payment) are added in later, separate migrations.
alter type payment_status_enum add value 'PARTIAL';
commit;

begin;
-- Phase 3 (Deposit / Outstanding Balance): complete_sale gains one new,
-- explicit, opt-in parameter -- p_allow_partial_payment boolean default
-- false. Every existing caller (the POS checkout screen, via
-- PosRepository.completeSale) sends a JSON object without this key, so
-- PostgREST applies the default (false) and the existing full-payment-only
-- behavior is completely unchanged for the normal checkout path -- it is
-- structurally impossible to activate the new behavior by accident, since
-- doing so requires a deliberate Flutter code change to start sending
-- p_allow_partial_payment: true.
--
-- Because this adds a parameter (changing the function's argument-type
-- signature, not just its body), a plain CREATE OR REPLACE would create a
-- second overload rather than replacing the existing one -- so the old
-- 9-argument signature is dropped first.
--
-- Two behavioral changes inside the function body, both gated on the new
-- parameter:
--   1) The existing "p_paid_amount < v_total" rejection now only fires
--      when p_allow_partial_payment is not true (zero payment is still
--      always rejected, in both modes -- a deposit must be > 0).
--   2) v_payment_status is now COMPLETED or PARTIAL depending on whether
--      p_paid_amount >= v_total, instead of being hardcoded to COMPLETED.
--      This is the correct resolution of the F7-2 concern the hardcoded
--      value was originally papering over ("a sale with $0 paid was fully
--      processed with no distinguishing marker") -- now there is a real,
--      queryable distinguishing marker.
--   3) v_change is now `greatest(p_paid_amount - v_total, 0)` instead of
--      the bare subtraction -- required for correctness once p_paid_amount
--      can be less than v_total, since sales.change_amount has a
--      `check (change_amount >= 0)` constraint that the bare subtraction
--      would violate for any partial payment.
--
-- Every other line (auth guard, role check, idempotency, customer
-- validation, the two-pass authoritative price resolution from F7-1, stock
-- deduction, commission calculation, the payments insert itself -- which
-- stays hardcoded to 'COMPLETED', since an individual payment transaction
-- that itself succeeded is not "partial", only the sale's aggregate state
-- is -- customer stats update, audit log) is verbatim from
-- 0024_complete_sale_price_and_payment_integrity.sql.
drop function if exists complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
);

create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text,
  p_allow_partial_payment boolean default false
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_resolved_items jsonb := '[]'::jsonb;
  v_subtotal numeric(14,2) := 0;
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_unit_price numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
  v_quantity integer;
  v_discount numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  -- Pass 1: resolve each item's authoritative catalog price exactly once
  -- (never the client-supplied unit_price) and accumulate the sale's
  -- subtotal from those authoritative values.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::int, 1);
    v_discount := coalesce((v_item->>'discount_amount')::numeric, 0);
    v_service_commission_type := null;
    v_service_commission_value := null;

    if (v_item->>'item_type') = 'SERVICE' then
      select price, commission_type, commission_value
        into v_unit_price, v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_unit_price is null then
        raise exception 'Service not found in this business';
      end if;
    elsif (v_item->>'item_type') = 'PRODUCT' then
      select selling_price into v_unit_price
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_unit_price is null then
        raise exception 'Product not found in this business';
      end if;
    else
      raise exception 'Invalid item type';
    end if;

    v_item_subtotal := (v_unit_price * v_quantity) - v_discount;
    if v_item_subtotal < 0 then
      raise exception 'Discount cannot exceed the item subtotal';
    end if;

    v_subtotal := v_subtotal + v_item_subtotal;

    v_resolved_items := v_resolved_items || jsonb_build_object(
      'item_type', v_item->>'item_type',
      'service_id', nullif(v_item->>'service_id', ''),
      'product_id', nullif(v_item->>'product_id', ''),
      'staff_id', v_item->>'staff_id',
      'name_snapshot', v_item->>'name_snapshot',
      'quantity', v_quantity,
      'unit_price', v_unit_price,
      'discount_amount', v_discount,
      'item_subtotal', v_item_subtotal,
      'commission_type', v_service_commission_type,
      'commission_value', v_service_commission_value
    );
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  v_total := v_subtotal - coalesce(p_discount_amount, 0) + coalesce(p_tax_amount, 0);
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount = 0 then
    raise exception 'Payment amount must be greater than zero';
  elsif p_paid_amount < v_total and not coalesce(p_allow_partial_payment, false) then
    raise exception 'Payment amount cannot be less than the sale total';
  end if;

  v_payment_status := case when p_paid_amount >= v_total then 'COMPLETED' else 'PARTIAL' end;
  v_change := greatest(p_paid_amount - v_total, 0);

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), coalesce(p_tax_amount, 0), v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  -- Pass 2: persist each line using the already-resolved authoritative
  -- price/subtotal from pass 1 -- no re-query of services/products for
  -- price. Stock sufficiency is still checked and deducted here, in the
  -- same order as before the fix, so two lines referencing the same
  -- product still interact correctly (the lock was already taken in
  -- pass 1, so this re-read is immediate, not blocking).
  for v_item in select * from jsonb_array_elements(v_resolved_items)
  loop
    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    v_commission_amount := 0;
    if (v_item->>'item_type') = 'SERVICE' and v_staff_valid and (v_item->>'commission_type') is not null then
      if (v_item->>'commission_type') = 'PERCENTAGE' then
        v_commission_amount := round(
          (v_item->>'item_subtotal')::numeric * coalesce((v_item->>'commission_value')::numeric, 0) / 100, 2
        );
      else
        v_commission_amount := coalesce((v_item->>'commission_value')::numeric, 0);
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric, (v_item->>'discount_amount')::numeric,
      (v_item->>'item_subtotal')::numeric, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid
        for update;

      if v_product_stock < (v_item->>'quantity')::int then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      update products set stock_quantity = stock_quantity - (v_item->>'quantity')::int
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -(v_item->>'quantity')::int, 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        (v_item->>'commission_type')::commission_kind, coalesce((v_item->>'commission_value')::numeric, 0),
        v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, 'COMPLETED', auth.uid());

  if p_customer_id is not null then
    perform set_config('app.trusted_customer_stats_update', 'true', true);
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) to authenticated;

-- Phase 3 (Deposit / Outstanding Balance): record_sale_payment -- the
-- authoritative RPC for recording an additional payment against an
-- existing sale and settling (fully or partially) its outstanding balance.
--
-- protect_sales_snapshot_columns (0022) currently blocks ANY change to
-- sales.paid_amount on UPDATE, full stop -- correct at the time, since no
-- legitimate code path ever needed to update an existing sale's paid_amount
-- (complete_sale only ever INSERTs; this trigger fires on UPDATE only, so
-- complete_sale was never affected by it). record_sale_payment is the first
-- legitimate reason to update it, so the trigger gains a narrow,
-- opt-in-by-trusted-context exception -- the exact same pattern already
-- proven safe in 0023_complete_sale_customer_integrity.sql for
-- customers.total_spent/visit_count/last_visit_at: a transaction-local
-- set_config flag that only this RPC sets, immediately before its own
-- UPDATE, inside the same transaction. A client cannot forge this context
-- (set_config is a pg_catalog builtin, never exposed as a PostgREST RPC,
-- and the flag is scoped to this transaction only). Every other blocked
-- column (business_id, branch_id, customer_id, cashier_id, receipt_number,
-- subtotal, discount_amount, tax_amount, total_amount, change_amount,
-- idempotency_key, created_at) is completely untouched -- still
-- unconditionally blocked, exactly as before. payment_status was never
-- blocked by this trigger (it isn't in the original column list), so it
-- needs no special-case handling.
create or replace function protect_sales_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.branch_id is distinct from old.branch_id
     or new.customer_id is distinct from old.customer_id
     or new.cashier_id is distinct from old.cashier_id
     or new.receipt_number is distinct from old.receipt_number
     or new.subtotal is distinct from old.subtotal
     or new.discount_amount is distinct from old.discount_amount
     or new.tax_amount is distinct from old.tax_amount
     or new.total_amount is distinct from old.total_amount
     or new.change_amount is distinct from old.change_amount
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial, attribution, or identity fields on an existing sale -- only status and void metadata may be updated';
  end if;

  if new.paid_amount is distinct from old.paid_amount
     and coalesce(current_setting('app.trusted_sale_settlement_update', true), '') <> 'true'
  then
    raise exception 'Cannot modify paid_amount on an existing sale outside the settlement RPC';
  end if;

  return new;
end;
$$;

-- record_sale_payment: mirrors the auth/role/tenant/locking pattern already
-- proven by void_sale and set_appointment_status. Never trusts a
-- client-supplied balance or paid_amount -- both are recomputed here from
-- the payments table (the append-only source of truth) and the locked
-- sales row, every time.
--
-- Concurrency safety: the sales row is locked FOR UPDATE before the
-- outstanding balance is computed, and held until the new payment is
-- inserted and sales.paid_amount is updated, all in one transaction. Two
-- concurrent calls against the same sale therefore serialize: the second
-- caller blocks on the lock, then (once it resumes) recomputes the
-- outstanding balance from the now-updated payments/sales state, so it can
-- never accept a payment that would push paid_amount past total_amount --
-- there is no window where both calls compute the balance from the same
-- stale snapshot.
create or replace function record_sale_payment(
  p_business_id uuid,
  p_sale_id uuid,
  p_payment_method payment_method_enum,
  p_amount numeric,
  p_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_payment payments;
  v_paid_amount numeric(14,2);
  v_outstanding numeric(14,2);
  v_new_paid_amount numeric(14,2);
  v_new_outstanding numeric(14,2);
  v_new_payment_status payment_status_enum;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a payment';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Cannot record a payment against a % sale', v_sale.status;
  end if;

  -- Authoritative paid amount: sum of this sale's non-reversed payments,
  -- never the client, never a stale sales.paid_amount snapshot (though in
  -- practice they always agree, since this function is the only writer of
  -- both after the initial complete_sale insert).
  select coalesce(sum(amount), 0) into v_paid_amount
    from payments where sale_id = p_sale_id and status <> 'REFUNDED';

  v_outstanding := v_sale.total_amount - v_paid_amount;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  if v_outstanding <= 0 then
    raise exception 'This sale is already fully paid';
  end if;

  if p_amount > v_outstanding then
    raise exception 'Payment amount cannot exceed the outstanding balance of %', v_outstanding;
  end if;

  insert into payments (business_id, sale_id, payment_method, amount, reference, status, created_by)
  values (p_business_id, p_sale_id, p_payment_method, p_amount, p_reference, 'COMPLETED', auth.uid())
  returning * into v_payment;

  v_new_paid_amount := v_paid_amount + p_amount;
  v_new_outstanding := v_sale.total_amount - v_new_paid_amount;
  v_new_payment_status := case when v_new_outstanding <= 0 then 'COMPLETED' else 'PARTIAL' end;

  perform set_config('app.trusted_sale_settlement_update', 'true', true);
  update sales set
    paid_amount = v_new_paid_amount,
    payment_status = v_new_payment_status
    where id = p_sale_id
    returning * into v_sale;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', p_sale_id, to_jsonb(v_payment));

  return jsonb_build_object(
    'payment_id', v_payment.id,
    'payment_amount', v_payment.amount,
    'total_amount', v_sale.total_amount,
    'paid_amount', v_sale.paid_amount,
    'outstanding_balance', greatest(v_new_outstanding, 0),
    'payment_status', v_sale.payment_status
  );
end;
$$;

revoke execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) from public;
revoke execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) from anon;
grant execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) to authenticated;

-- Phase 3 (Deposit / Outstanding Balance): void_sale extension.
--
-- Every line here is verbatim from 0038_void_sale_package_guard.sql (which
-- itself is verbatim from 0026_void_sale.sql except the package-redemption
-- guard) except one new field in the final `update sales set ...` --
-- payment_status = 'REFUNDED' alongside the existing status = 'VOIDED'.
--
-- Decision, per the Phase 3 audit (Step 8): a partially paid sale MAY be
-- voided -- there is no reason to forbid it (unlike the package-redemption
-- guard immediately below, which blocks voiding when real, non-reversible
-- service delivery already happened; a partial cash payment has no such
-- irreversibility). paid_amount is deliberately left untouched here, exactly
-- as before this migration -- it remains the true historical record of what
-- was actually collected before the void, satisfying "must not silently
-- lose payment history." The existing
-- `update payments set status = 'REFUNDED' where sale_id = p_sale_id and
-- status <> 'REFUNDED'` line already correctly marks EVERY payment row for
-- the sale (not just one), so it required no change to already support
-- multiple payments -- confirmed by inspection, not assumed.
--
-- True partial refunds (returning only some of what was paid, as a
-- distinct amount-tracked transaction) are explicitly OUT OF SCOPE for this
-- migration -- see the Phase 3 implementation report's Step 8/Section 6 for
-- the documented limitation. This migration only makes the existing
-- status-only refund model correctly reflect PARTIAL-paid sales too.
create or replace function void_sale(
  p_business_id uuid,
  p_sale_id uuid,
  p_reason text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_old_sale jsonb;
  v_item record;
  v_product products;
  v_reversed_commission_count int := 0;
  v_reversed_inventory_count int := 0;
  v_skipped_product_deleted_count int := 0;
  v_customer_package customer_packages;
  v_has_redemptions boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to void a sale';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A void reason is required';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Only a completed sale can be voided';
  end if;

  v_old_sale := to_jsonb(v_sale);

  select * into v_customer_package from customer_packages where sale_id = p_sale_id;

  if v_customer_package.id is not null then
    select exists (
      select 1 from customer_package_items
      where customer_package_id = v_customer_package.id and used_sessions > 0
    ) into v_has_redemptions;

    if v_has_redemptions then
      raise exception 'Cannot void a package sale that has redeemed sessions';
    end if;
  end if;

  for v_item in
    select * from sale_items where sale_id = p_sale_id and item_type = 'PRODUCT'
  loop
    if v_item.product_id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    select * into v_product from products
      where id = v_item.product_id and business_id = p_business_id
      for update;

    if v_product.id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    update products set stock_quantity = stock_quantity + v_item.quantity
      where id = v_item.product_id;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, reference_id, note, created_by
    ) values (
      p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_item.quantity,
      'sale_void', p_sale_id, 'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
    );

    v_reversed_inventory_count := v_reversed_inventory_count + 1;
  end loop;

  update commissions set status = 'REVERSED'
    where sale_id = p_sale_id and status <> 'REVERSED';
  get diagnostics v_reversed_commission_count = row_count;

  update sales set
    status = 'VOIDED',
    payment_status = 'REFUNDED',
    void_reason = p_reason,
    voided_by = auth.uid(),
    voided_at = now()
    where id = p_sale_id
    returning * into v_sale;

  update payments set status = 'REFUNDED'
    where sale_id = p_sale_id and status <> 'REFUNDED';

  -- Phase 2: cancel the (unused) package entitlement alongside the sale.
  if v_customer_package.id is not null then
    update customer_packages set status = 'CANCELLED' where id = v_customer_package.id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'VOID', 'sale', p_sale_id, v_old_sale, to_jsonb(v_sale),
    jsonb_build_object(
      'reason', p_reason,
      'reversed_commission_count', v_reversed_commission_count,
      'reversed_inventory_line_count', v_reversed_inventory_count,
      'skipped_product_deleted_lines', v_skipped_product_deleted_count,
      'package_cancelled', v_customer_package.id is not null
    )
  );

  return v_sale;
end;
$$;

revoke execute on function void_sale(uuid, uuid, text) from public;
revoke execute on function void_sale(uuid, uuid, text) from anon;
grant execute on function void_sale(uuid, uuid, text) to authenticated;
commit;

begin;
-- Phase 4: Customer Treatment History.
--
-- A dedicated, separate service-delivery/history domain -- explicitly NOT
-- merged into sales (financial transaction) or overloaded onto
-- appointments (booking metadata). appointment_id/appointment_item_id/
-- sale_id are optional cross-references only, never a hard dependency:
-- a walk-in customer with no appointment can still get a treatment
-- record via the manual path (create_treatment_record below).
--
-- FK deletion behavior follows this schema's own established conventions,
-- not guessed:
--   - business_id: on delete cascade (every business-owned table).
--   - customer_id (required, not null): on delete restrict, matching
--     customer_packages.customer_id -- the same "required customer FK on a
--     historical/financial-adjacent record" shape.
--   - appointment_id / appointment_item_id / sale_id (all optional):
--     on delete set null, matching customer_packages.sale_id and
--     appointments.customer_id -- a treatment record must survive even if
--     the appointment/sale it references is later removed; it never
--     cascades away.
--   - service_id (required, not null): on delete restrict, matching
--     appointment_items.service_id/package_items.service_id -- the same
--     "required catalog FK, preserved via snapshot + RESTRICT" shape used
--     everywhere else in this schema.
--   - staff_id (required, not null): on delete restrict, matching
--     appointments.staff_id/sales.cashier_id.
--   - created_by (optional): on delete set null, matching
--     appointments.created_by.
--
-- Snapshot requirement: service_name_snapshot/staff_name_snapshot are
-- captured together with their FK at creation time (both RPCs below
-- resolve them server-side, never from client input) -- the snapshot
-- represents what the treatment meant at treatment time and is never
-- rewritten by a later service rename or staff profile change. The FK
-- remains the authoritative live relationship for navigation; the
-- snapshot is display-only history, the same dual pattern already used by
-- appointment_items.name_snapshot, sale_items.name_snapshot, and
-- customer_packages.name_snapshot.
--
-- Idempotency: treatment_history_appointment_item_unique (a partial
-- unique index, not a table-wide constraint -- NULL appointment_item_id
-- rows, i.e. walk-in treatments, are simply not covered by it) is the
-- DB-level guarantee that one appointment_item produces at most one
-- auto-created treatment record, mirroring
-- customer_package_redemptions_appointment_item_unique (0032) exactly.
-- This is defense-in-depth: set_appointment_status's own state machine
-- already makes a second COMPLETED transition on the same appointment
-- structurally impossible (COMPLETED has no outbound transitions), so a
-- true duplicate-invocation race is not actually reachable through the
-- RPC -- the index protects against it regardless, the same way the
-- package-redemption index does for a scenario its own state machine also
-- already prevents.
create table treatment_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete set null,
  appointment_item_id uuid references appointment_items(id) on delete set null,
  sale_id uuid references sales(id) on delete set null,
  service_id uuid not null references services(id) on delete restrict,
  staff_id uuid not null references profiles(id) on delete restrict,
  service_name_snapshot text not null,
  staff_name_snapshot text not null,
  treatment_date timestamptz not null,
  notes text,
  result text,
  customer_feedback text,
  before_after_reference text,
  follow_up_date date,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index treatment_history_business_id_idx on treatment_history(business_id);
create index treatment_history_customer_id_idx
  on treatment_history(business_id, customer_id, treatment_date desc);
create index treatment_history_appointment_id_idx on treatment_history(appointment_id);
create index treatment_history_service_id_idx on treatment_history(service_id);
create index treatment_history_staff_id_idx on treatment_history(staff_id);

create unique index treatment_history_appointment_item_unique
  on treatment_history(appointment_item_id)
  where appointment_item_id is not null;

create trigger treatment_history_set_updated_at
  before update on treatment_history
  for each row execute function set_updated_at();

-- Column protection: only the narrative fields (notes, result,
-- customer_feedback, before_after_reference, follow_up_date) may be
-- edited on an existing row -- identity/snapshot/attribution fields are
-- permanently fixed at creation, the same BEFORE UPDATE trigger shape
-- already proven for sales/payments/commissions (0022).
create or replace function protect_treatment_history_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.appointment_id is distinct from old.appointment_id
     or new.appointment_item_id is distinct from old.appointment_item_id
     or new.sale_id is distinct from old.sale_id
     or new.service_id is distinct from old.service_id
     or new.staff_id is distinct from old.staff_id
     or new.service_name_snapshot is distinct from old.service_name_snapshot
     or new.staff_name_snapshot is distinct from old.staff_name_snapshot
     or new.treatment_date is distinct from old.treatment_date
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity or snapshot fields on an existing treatment record -- only notes, result, customer_feedback, before_after_reference, and follow_up_date may be updated';
  end if;
  return new;
end;
$$;

create trigger treatment_history_protect_identity_columns
  before update on treatment_history
  for each row execute function protect_treatment_history_identity_columns();

alter table treatment_history enable row level security;

create policy treatment_history_select on treatment_history
  for select using (is_member(business_id));

-- No direct INSERT policy: both the auto-creation path
-- (set_appointment_status, below) and the manual/walk-in path
-- (create_treatment_record, below) are SECURITY DEFINER RPCs that resolve
-- and validate every FK/snapshot server-side -- matching the
-- appointments/customer_packages/sales pattern (RPC-only writes for
-- records with server-authoritative derived fields), rather than
-- duplicating write authority between a direct INSERT policy and an RPC.

create policy treatment_history_update on treatment_history
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: treatment history is immutable identity/append-only
-- narrative data, matching customer_notes/payments/inventory_movements --
-- corrections are edits to the narrative fields (still column-protected
-- above), never row removal.

-- create_treatment_record: the manual/walk-in entry path. Every
-- identity/snapshot value is resolved and validated server-side from
-- p_business_id-scoped lookups -- the client supplies only ids, dates,
-- and free-text narrative fields, never a name snapshot or a business/
-- tenant claim.
create or replace function create_treatment_record(
  p_business_id uuid,
  p_customer_id uuid,
  p_service_id uuid,
  p_staff_id uuid,
  p_treatment_date timestamptz,
  p_appointment_id uuid,
  p_appointment_item_id uuid,
  p_sale_id uuid,
  p_notes text,
  p_result text,
  p_customer_feedback text,
  p_before_after_reference text,
  p_follow_up_date date
)
returns treatment_history
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_service services;
  v_staff_valid boolean;
  v_staff_name text;
  v_appointment appointments;
  v_appointment_item appointment_items;
  v_record treatment_history;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a treatment';
  end if;

  if p_treatment_date is null then
    raise exception 'Treatment date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_service from services
    where id = p_service_id and business_id = p_business_id;
  if v_service.id is null then
    raise exception 'Service not found in this business';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_staff_id;

  if p_appointment_id is not null then
    select * into v_appointment from appointments
      where id = p_appointment_id and business_id = p_business_id;
    if v_appointment.id is null then
      raise exception 'Appointment not found in this business';
    end if;
    if v_appointment.customer_id is distinct from p_customer_id then
      raise exception 'This appointment does not belong to the selected customer';
    end if;
  end if;

  if p_appointment_item_id is not null then
    if p_appointment_id is null then
      raise exception 'An appointment item requires its appointment';
    end if;
    select * into v_appointment_item from appointment_items
      where id = p_appointment_item_id
        and appointment_id = p_appointment_id
        and business_id = p_business_id;
    if v_appointment_item.id is null then
      raise exception 'Appointment item not found for this appointment';
    end if;
  end if;

  if p_sale_id is not null and not exists (
    select 1 from sales where id = p_sale_id and business_id = p_business_id
  ) then
    raise exception 'Sale not found in this business';
  end if;

  begin
    insert into treatment_history (
      business_id, customer_id, appointment_id, appointment_item_id, sale_id,
      service_id, staff_id, service_name_snapshot, staff_name_snapshot, treatment_date,
      notes, result, customer_feedback, before_after_reference, follow_up_date, created_by
    ) values (
      p_business_id, p_customer_id, p_appointment_id, p_appointment_item_id, p_sale_id,
      p_service_id, p_staff_id, v_service.name, coalesce(v_staff_name, ''), p_treatment_date,
      p_notes, p_result, p_customer_feedback, p_before_after_reference, p_follow_up_date, auth.uid()
    ) returning * into v_record;
  exception
    when unique_violation then
      raise exception 'A treatment record already exists for this appointment item';
  end;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'treatment_history', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) from public;
revoke execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) from anon;
grant execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) to authenticated;

-- set_appointment_status: every line above the "-- Phase 4:" marker is
-- verbatim from 0037_package_rpcs.sql (the current live version) -- auth
-- guard, role check, state machine, the existing status update and its
-- audit_logs insert, and the Phase 2 package-redemption loop are all
-- byte-for-byte unchanged. Only a new loop is appended after the existing
-- package-redemption loop, inside the same `if p_status = 'COMPLETED'`
-- block, so both run in the same transaction as the status transition --
-- any failure anywhere rolls back the whole call, including the status
-- update, so an appointment can never end up COMPLETED with missing
-- treatment history.
--
-- The new loop iterates every appointment_item for the appointment (not
-- just package-linked ones -- treatment history applies to every service
-- delivered, package-covered or not), reusing
-- appointment_items.name_snapshot directly as service_name_snapshot --
-- safe to trust verbatim since P1-01
-- (0041_book_appointment_authoritative_price.sql) made that column
-- server-derived from services.name at booking time, never client-
-- supplied. staff_id falls back to the appointment's own staff_id when an
-- item has none, matching the exact same coalesce already used for
-- commission attribution a few lines below in the existing package loop.
-- A customer-less appointment (p_customer_id was optional at booking) is
-- skipped entirely -- treatment_history.customer_id is NOT NULL, so no
-- treatment record can be created without one; this is expected, not an
-- error.
create or replace function set_appointment_status(
  p_business_id uuid,
  p_appointment_id uuid,
  p_status appointment_status,
  p_cancel_reason text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
  v_allowed appointment_status[];
  v_appt_item appointment_items;
  v_cpi customer_package_items;
  v_cp customer_packages;
  v_redemption customer_package_redemptions;
  v_staff_id uuid;
  v_staff_valid boolean;
  v_commission_type commission_kind;
  v_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_staff_name text;
  v_treatment_record treatment_history;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to change appointment status';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  v_allowed := case v_appointment.status
    when 'SCHEDULED' then array['CONFIRMED', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CONFIRMED' then array['CHECKED_IN', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CHECKED_IN' then array['COMPLETED', 'CANCELLED']::appointment_status[]
    else array[]::appointment_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move an appointment from % to %', v_appointment.status, p_status;
  end if;

  v_old_data := to_jsonb(v_appointment);

  update appointments set
    status = p_status,
    cancel_reason = case when p_status = 'CANCELLED' then p_cancel_reason else cancel_reason end
  where id = p_appointment_id
  returning * into v_appointment;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  -- Phase 2: completion-time package redemption.
  if p_status = 'COMPLETED' then
    for v_appt_item in
      select * from appointment_items
      where appointment_id = p_appointment_id and customer_package_item_id is not null
    loop
      select * into v_cpi from customer_package_items
        where id = v_appt_item.customer_package_item_id and business_id = p_business_id
        for update;

      if v_cpi.id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      select * into v_cp from customer_packages where id = v_cpi.customer_package_id;

      if v_cp.customer_id is distinct from v_appointment.customer_id then
        raise exception 'This package entitlement does not belong to the appointment''s customer';
      end if;

      if v_cpi.service_id is distinct from v_appt_item.service_id then
        raise exception 'This package entitlement does not cover the booked service';
      end if;

      if v_cp.status <> 'ACTIVE' then
        raise exception 'This package is not active';
      end if;

      if v_cp.expires_at is not null and v_cp.expires_at < now() then
        raise exception 'This package has expired';
      end if;

      if v_cpi.used_sessions >= v_cpi.total_sessions then
        raise exception 'No remaining sessions on this package entitlement';
      end if;

      if exists (
        select 1 from customer_package_redemptions
        where appointment_item_id = v_appt_item.id and not reversed
      ) then
        raise exception 'This service has already been redeemed against a package';
      end if;

      update customer_package_items set used_sessions = used_sessions + 1
        where id = v_cpi.id
        returning * into v_cpi;

      v_staff_id := coalesce(v_appt_item.staff_id, v_appointment.staff_id);

      insert into customer_package_redemptions (
        business_id, customer_package_item_id, appointment_id, appointment_item_id, staff_id
      ) values (
        p_business_id, v_cpi.id, p_appointment_id, v_appt_item.id, v_staff_id
      ) returning * into v_redemption;

      insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
      values (p_business_id, auth.uid(), 'CREATE', 'customer_package_redemption', v_redemption.id, to_jsonb(v_redemption));

      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id and user_id = v_staff_id and active = true
      );

      select commission_type, commission_value into v_commission_type, v_commission_value
        from services where id = v_appt_item.service_id and business_id = p_business_id;

      v_commission_amount := 0;
      if v_staff_valid and v_commission_type is not null then
        if v_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_appt_item.price_snapshot * coalesce(v_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_commission_value, 0);
        end if;
      end if;

      if v_commission_amount > 0 then
        insert into commissions (
          business_id, customer_package_redemption_id, staff_id, commission_type,
          commission_rate, commission_amount, status
        ) values (
          p_business_id, v_redemption.id, v_staff_id,
          v_commission_type, coalesce(v_commission_value, 0), v_commission_amount, 'PENDING'
        );
      end if;
    end loop;

    -- Phase 4: one treatment_history row per appointment item, for every
    -- item (package-linked or not). Skipped entirely for a customer-less
    -- appointment -- see header.
    if v_appointment.customer_id is not null then
      for v_appt_item in
        select * from appointment_items where appointment_id = p_appointment_id
      loop
        select full_name into v_staff_name from profiles
          where id = coalesce(v_appt_item.staff_id, v_appointment.staff_id);

        insert into treatment_history (
          business_id, customer_id, appointment_id, appointment_item_id, sale_id,
          service_id, staff_id, service_name_snapshot, staff_name_snapshot, treatment_date, created_by
        ) values (
          p_business_id, v_appointment.customer_id, p_appointment_id, v_appt_item.id, v_appointment.sale_id,
          v_appt_item.service_id, coalesce(v_appt_item.staff_id, v_appointment.staff_id),
          v_appt_item.name_snapshot, coalesce(v_staff_name, ''), v_appointment.start_at, auth.uid()
        )
        on conflict (appointment_item_id) where appointment_item_id is not null do nothing
        returning * into v_treatment_record;

        if v_treatment_record.id is not null then
          insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
          values (p_business_id, auth.uid(), 'CREATE', 'treatment_history', v_treatment_record.id, to_jsonb(v_treatment_record));
        end if;
      end loop;
    end if;
  end if;

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;
commit;

begin;
-- Phase 5: Consultation / Customer Consultation Records.
--
-- A dedicated, separate domain from customer_notes (generic free-text),
-- appointments (booking metadata), treatment_history (what was
-- delivered), and sales (financial transaction) -- following the exact
-- architectural template Phase 4 already established for
-- treatment_history (0047_treatment_history.sql).
--
-- Canonical flow: Customer -> Consultation -> optional Appointment ->
-- Treatment. Every arrow is optional except the first: a consultation
-- never requires a treatment, a treatment never requires a consultation,
-- and a consultation never requires an appointment (walk-in consultation
-- is a required Phase 5 path). Unlike treatment_history, there is no
-- auto-creation path at all -- every consultation is created explicitly,
-- so there is no state-machine hook and no idempotency concern to design
-- for (multiple consultations for the same customer, or even the same
-- appointment, are legitimate business scenarios, not duplicates).
--
-- FK deletion behavior, inspected from the actual existing schema, not
-- guessed:
--   - business_id: on delete cascade (every business-owned table).
--   - customer_id (required, not null): on delete restrict, matching
--     treatment_history.customer_id/customer_packages.customer_id.
--   - appointment_id (optional): on delete set null, matching
--     treatment_history.appointment_id.
--   - staff_id (required, not null): on delete restrict, matching
--     treatment_history.staff_id/appointments.staff_id.
--   - recommended_service_id (optional): on delete set null -- this
--     schema's consistent rule for every OPTIONAL catalog FK (e.g.
--     treatment_history.appointment_id/sale_id), as opposed to the
--     RESTRICT used for REQUIRED catalog FKs like
--     treatment_history.service_id. The recommended_service_name_snapshot
--     column preserves what was actually recommended even after the live
--     service row is gone.
--   - created_by (optional): on delete set null, matching
--     treatment_history.created_by/appointments.created_by.
--
-- Snapshot requirement: staff_name_snapshot is always resolved and stored
-- server-side (required, not null). recommended_service_name_snapshot is
-- resolved server-side only when recommended_service_id is supplied --
-- enforced by a CHECK constraint (both null together, or both non-null
-- together), not merely by RPC discipline, so the invariant holds
-- regardless of write path.
--
-- No idempotency/uniqueness constraint: per the approved Phase 5 scope,
-- multiple consultations for the same customer (or even the same
-- appointment) are legitimate and must not be blocked. This is a
-- deliberate difference from treatment_history's
-- appointment_item_id partial unique index, which exists specifically
-- because that domain has a real duplicate-prevention requirement
-- (one appointment_item -> at most one auto-created record); no
-- equivalent requirement exists here since there is no auto-creation path.
create table consultations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete set null,
  staff_id uuid not null references profiles(id) on delete restrict,
  staff_name_snapshot text not null,
  recommended_service_id uuid references services(id) on delete set null,
  recommended_service_name_snapshot text,
  consultation_date timestamptz not null,
  consultation_notes text,
  customer_concerns text,
  observations text,
  considerations text,
  assessment text,
  recommendation_notes text,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint consultations_recommended_service_snapshot_chk check (
    (recommended_service_id is null and recommended_service_name_snapshot is null)
    or
    (recommended_service_id is not null and recommended_service_name_snapshot is not null)
  )
);

create index consultations_business_id_idx on consultations(business_id);
create index consultations_customer_id_idx
  on consultations(business_id, customer_id, consultation_date desc);
create index consultations_appointment_id_idx on consultations(appointment_id);
create index consultations_staff_id_idx on consultations(staff_id);

create trigger consultations_set_updated_at
  before update on consultations
  for each row execute function set_updated_at();

-- Column protection: only the narrative fields (consultation_notes,
-- customer_concerns, observations, considerations, assessment,
-- recommendation_notes) may be edited on an existing row -- identity/
-- snapshot/attribution fields are permanently fixed at creation, the same
-- BEFORE UPDATE trigger shape already proven for treatment_history (0047)
-- and, before that, sales/payments/commissions (0022). IS DISTINCT FROM
-- means a same-value write is a harmless no-op, not a bypass -- a genuine
-- identity change is what gets rejected.
create or replace function protect_consultation_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.appointment_id is distinct from old.appointment_id
     or new.staff_id is distinct from old.staff_id
     or new.staff_name_snapshot is distinct from old.staff_name_snapshot
     or new.recommended_service_id is distinct from old.recommended_service_id
     or new.recommended_service_name_snapshot is distinct from old.recommended_service_name_snapshot
     or new.consultation_date is distinct from old.consultation_date
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity or snapshot fields on an existing consultation record -- only consultation_notes, customer_concerns, observations, considerations, assessment, and recommendation_notes may be updated';
  end if;
  return new;
end;
$$;

create trigger consultations_protect_identity_columns
  before update on consultations
  for each row execute function protect_consultation_identity_columns();

alter table consultations enable row level security;

create policy consultations_select on consultations
  for select using (is_member(business_id));

-- No direct INSERT policy: creation is exclusively through
-- create_treatment_record's sibling below, create_consultation_record --
-- matching the RPC-only pattern already established for
-- appointments/customer_packages/sales/treatment_history.

create policy consultations_update on consultations
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: consultations are immutable identity/append-only
-- narrative data, matching treatment_history/customer_notes/payments --
-- corrections are narrative edits (still column-protected above), never
-- row removal. No ADMIN delete escape hatch is introduced.

-- create_consultation_record: every identity/snapshot value is resolved
-- and validated server-side from p_business_id-scoped lookups -- the
-- client supplies only ids, the consultation date, and free-text
-- narrative fields, never a name snapshot or a business/tenant claim.
-- Staff is always the explicitly supplied p_staff_id -- an appointment's
-- own staff_id (if any) is never substituted, since a consultation is not
-- an appointment-completion side effect and has no existing project
-- semantics requiring that override.
create or replace function create_consultation_record(
  p_business_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_consultation_date timestamptz,
  p_appointment_id uuid,
  p_recommended_service_id uuid,
  p_consultation_notes text,
  p_customer_concerns text,
  p_observations text,
  p_considerations text,
  p_assessment text,
  p_recommendation_notes text
)
returns consultations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_staff_valid boolean;
  v_staff_name text;
  v_appointment appointments;
  v_service services;
  v_record consultations;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a consultation';
  end if;

  if p_consultation_date is null then
    raise exception 'Consultation date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_staff_id;

  if p_appointment_id is not null then
    select * into v_appointment from appointments
      where id = p_appointment_id and business_id = p_business_id;
    if v_appointment.id is null then
      raise exception 'Appointment not found in this business';
    end if;
    if v_appointment.customer_id is distinct from p_customer_id then
      raise exception 'This appointment does not belong to the selected customer';
    end if;
  end if;

  if p_recommended_service_id is not null then
    select * into v_service from services
      where id = p_recommended_service_id and business_id = p_business_id;
    if v_service.id is null then
      raise exception 'Recommended service not found in this business';
    end if;
  end if;

  insert into consultations (
    business_id, customer_id, appointment_id, staff_id, staff_name_snapshot,
    recommended_service_id, recommended_service_name_snapshot, consultation_date,
    consultation_notes, customer_concerns, observations, considerations,
    assessment, recommendation_notes, created_by
  ) values (
    p_business_id, p_customer_id, p_appointment_id, p_staff_id, coalesce(v_staff_name, ''),
    p_recommended_service_id,
    case when p_recommended_service_id is not null then v_service.name else null end,
    p_consultation_date,
    p_consultation_notes, p_customer_concerns, p_observations, p_considerations,
    p_assessment, p_recommendation_notes, auth.uid()
  ) returning * into v_record;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'consultation', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) from public;
revoke execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) from anon;
grant execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) to authenticated;
commit;

begin;
-- Phase 6: Follow-up / Reminder + LINE OA integration.
--
-- Five new tables, following the exact architectural template Phase 4/5
-- established: dedicated domains, snapshot+FK pattern, RPC-only writes
-- for anything server-authoritative, narrative-only direct-RLS UPDATE
-- where applicable, no DELETE policy on historical records.
--
-- follow_ups: staff-managed customer follow-up records. DUE/OVERDUE are
-- explicitly NOT stored -- they are always derived from
-- (status = 'PENDING' and due_date compared to now()), computed at query
-- time, avoiding any cron-driven state-flipping and any possibility of
-- stored state disagreeing with reality.
--
-- customer_line_accounts: the trusted LINE user <-> customer link.
-- Never written by the client -- only by the signature-verified webhook
-- Edge Function (via the service_role key, which bypasses RLS) or by the
-- unlink_customer_line_account RPC below (delete only, no client-supplied
-- line_user_id is ever accepted anywhere in this migration).
--
-- customer_line_link_codes: a short-lived, single-use, staff-generated
-- code that correlates a specific (business_id, customer_id) to whatever
-- LINE account later sends that code to the OA. This is the mechanism
-- that lets the webhook trust the eventual line_user_id it receives
-- directly from LINE's own signed payload, while still tying it to the
-- correct tenant/customer -- Flutter never supplies or sees a line_user_id
-- anywhere in this flow.
--
-- follow_up_notifications: the reminder delivery ledger. UNIQUE on
-- follow_up_id enforces "one reminder per follow-up" at the database
-- level. claim_due_follow_up_reminders/claim_failed_follow_up_notifications
-- (both service_role-only) are the atomic-claim mechanism -- the INSERT
-- ... ON CONFLICT DO NOTHING / UPDATE ... WHERE status = ... are
-- themselves the concurrency-safety guarantee (no "check then send"
-- window exists), the same class of technique already proven in this
-- project by record_sale_payment/void_sale's row-locking.
--
-- FK deletion behavior, inspected from actual existing precedent, not
-- guessed:
--   - business_id: on delete cascade everywhere (every business-owned table).
--   - follow_ups.customer_id/assigned_staff_id (required): restrict,
--     matching treatment_history/consultations' own required-FK shape.
--   - follow_ups.consultation_id/treatment_history_id/appointment_id/
--     created_by/completed_by (all optional): set null, matching
--     consultations' own optional-cross-reference shape.
--   - customer_line_accounts.customer_id: cascade -- unlike follow_ups/
--     treatment_history/consultations, this table has no historical-
--     record semantics worth preserving after a customer is deleted; it
--     is pure operational linkage metadata.
--   - customer_line_link_codes.customer_id: cascade, same reasoning.
--   - follow_up_notifications.follow_up_id: cascade -- a notification
--     ledger row has no independent meaning without its parent follow-up.
--   - follow_up_notifications.customer_line_account_id: set null --
--     preserves the delivery-attempt record even if the link is later
--     removed.
create type follow_up_status as enum ('PENDING', 'COMPLETED', 'MISSED', 'CANCELLED');
create type follow_up_notification_status as enum ('PENDING', 'SENDING', 'SENT', 'FAILED');

create table follow_ups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  assigned_staff_id uuid not null references profiles(id) on delete restrict,
  assigned_staff_name_snapshot text not null,
  consultation_id uuid references consultations(id) on delete set null,
  treatment_history_id uuid references treatment_history(id) on delete set null,
  appointment_id uuid references appointments(id) on delete set null,
  due_date timestamptz not null,
  status follow_up_status not null default 'PENDING',
  follow_up_notes text,
  completed_at timestamptz,
  completed_by uuid references profiles(id) on delete set null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index follow_ups_customer_idx on follow_ups(business_id, customer_id, due_date);
create index follow_ups_status_due_idx on follow_ups(business_id, status, due_date);
create index follow_ups_assigned_staff_idx on follow_ups(assigned_staff_id);

create trigger follow_ups_set_updated_at
  before update on follow_ups
  for each row execute function set_updated_at();

-- Column protection, two tiers:
--   1) Permanently fixed, never changeable by anyone, any path:
--      business_id, customer_id, consultation_id, treatment_history_id,
--      appointment_id, created_by, created_at.
--   2) Lifecycle fields (assigned_staff_id/assigned_staff_name_snapshot/
--      due_date/status/completed_at/completed_by): changeable ONLY via
--      the trusted-context flag set by reschedule_follow_up/
--      set_follow_up_status below -- the same set_config/current_setting
--      pattern already proven for sales.paid_amount (0044) and
--      customers.total_spent (0023). A direct client UPDATE (which can
--      never set this transaction-local flag) can therefore only ever
--      change follow_up_notes.
create or replace function protect_follow_up_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.consultation_id is distinct from old.consultation_id
     or new.treatment_history_id is distinct from old.treatment_history_id
     or new.appointment_id is distinct from old.appointment_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity fields on an existing follow-up';
  end if;

  if (new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.assigned_staff_name_snapshot is distinct from old.assigned_staff_name_snapshot
      or new.due_date is distinct from old.due_date
      or new.status is distinct from old.status
      or new.completed_at is distinct from old.completed_at
      or new.completed_by is distinct from old.completed_by)
     and coalesce(current_setting('app.trusted_follow_up_lifecycle_update', true), '') <> 'true'
  then
    raise exception 'Cannot modify assigned staff, due date, status, or completion fields on an existing follow-up outside the reschedule/status-transition RPCs -- only follow_up_notes may be updated directly';
  end if;

  return new;
end;
$$;

create trigger follow_ups_protect_identity_columns
  before update on follow_ups
  for each row execute function protect_follow_up_identity_columns();

alter table follow_ups enable row level security;

create policy follow_ups_select on follow_ups
  for select using (is_member(business_id));

-- No direct INSERT policy: creation is exclusively through
-- create_follow_up below.

create policy follow_ups_update on follow_ups
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: follow-ups are immutable identity/append-only data,
-- matching treatment_history/consultations -- corrections are status
-- transitions (CANCELLED), never row removal.

-- customer_line_accounts: never written by any client-facing RPC with a
-- client-supplied line_user_id. Only the webhook Edge Function (service_role,
-- bypasses RLS) writes new links, resolving line_user_id exclusively from
-- LINE's own signed webhook payload. unlink_customer_line_account below is
-- the only client-facing mutation, and it only ever deletes.
create table customer_line_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  line_user_id text not null,
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, line_user_id),
  unique (business_id, customer_id)
);

create index customer_line_accounts_customer_idx on customer_line_accounts(business_id, customer_id);

create trigger customer_line_accounts_set_updated_at
  before update on customer_line_accounts
  for each row execute function set_updated_at();

alter table customer_line_accounts enable row level security;

create policy customer_line_accounts_select on customer_line_accounts
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: writes come only from the webhook
-- Edge Function (service_role) or unlink_customer_line_account (below).

-- customer_line_link_codes: short-lived, single-use, staff-generated
-- codes that let the webhook correlate an incoming LINE message to the
-- correct tenant/customer without ever trusting a client-supplied
-- line_user_id.
create table customer_line_link_codes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  code text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (code)
);

create index customer_line_link_codes_business_idx on customer_line_link_codes(business_id, customer_id);

alter table customer_line_link_codes enable row level security;

create policy customer_line_link_codes_select on customer_line_link_codes
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: created only by create_line_link_code
-- (below); consumed only by the webhook Edge Function (service_role).

-- follow_up_notifications: the reminder delivery ledger. UNIQUE on
-- follow_up_id is the DB-level "one reminder per follow-up" guarantee.
-- Written only by the two service_role-only claim functions and
-- complete_follow_up_notification below -- never by any client-facing
-- RPC or direct client write.
create table follow_up_notifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  follow_up_id uuid not null references follow_ups(id) on delete cascade,
  customer_line_account_id uuid references customer_line_accounts(id) on delete set null,
  status follow_up_notification_status not null default 'PENDING',
  attempt_count integer not null default 0,
  claimed_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (follow_up_id)
);

create index follow_up_notifications_status_idx on follow_up_notifications(business_id, status);

create trigger follow_up_notifications_set_updated_at
  before update on follow_up_notifications
  for each row execute function set_updated_at();

alter table follow_up_notifications enable row level security;

create policy follow_up_notifications_select on follow_up_notifications
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: written only by the service_role-only
-- functions below (claim_due_follow_up_reminders,
-- claim_failed_follow_up_notifications, complete_follow_up_notification).

--------------------------------------------------------------------------
-- create_follow_up: client-facing creation RPC.
--------------------------------------------------------------------------
create or replace function create_follow_up(
  p_business_id uuid,
  p_customer_id uuid,
  p_assigned_staff_id uuid,
  p_due_date timestamptz,
  p_follow_up_notes text,
  p_consultation_id uuid,
  p_treatment_history_id uuid,
  p_appointment_id uuid
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_staff_valid boolean;
  v_staff_name text;
  v_record follow_ups;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to create a follow-up';
  end if;

  if p_due_date is null then
    raise exception 'Due date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_assigned_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Assigned staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_assigned_staff_id;

  if p_consultation_id is not null and not exists (
    select 1 from consultations
    where id = p_consultation_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Consultation not found for this customer in this business';
  end if;

  if p_treatment_history_id is not null and not exists (
    select 1 from treatment_history
    where id = p_treatment_history_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Treatment record not found for this customer in this business';
  end if;

  if p_appointment_id is not null and not exists (
    select 1 from appointments
    where id = p_appointment_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Appointment not found for this customer in this business';
  end if;

  insert into follow_ups (
    business_id, customer_id, assigned_staff_id, assigned_staff_name_snapshot,
    consultation_id, treatment_history_id, appointment_id,
    due_date, status, follow_up_notes, created_by
  ) values (
    p_business_id, p_customer_id, p_assigned_staff_id, coalesce(v_staff_name, ''),
    p_consultation_id, p_treatment_history_id, p_appointment_id,
    p_due_date, 'PENDING', p_follow_up_notes, auth.uid()
  ) returning * into v_record;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'follow_up', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) from public;
revoke execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) from anon;
grant execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) to authenticated;

--------------------------------------------------------------------------
-- reschedule_follow_up: due_date + assigned_staff reassignment, PENDING
-- only. Re-derives the staff snapshot server-side if staff changes --
-- never trusts a client-supplied snapshot.
--------------------------------------------------------------------------
create or replace function reschedule_follow_up(
  p_business_id uuid,
  p_follow_up_id uuid,
  p_due_date timestamptz,
  p_assigned_staff_id uuid
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_follow_up follow_ups;
  v_staff_valid boolean;
  v_staff_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to reschedule a follow-up';
  end if;

  if p_due_date is null then
    raise exception 'Due date is required';
  end if;

  select * into v_follow_up from follow_ups
    where id = p_follow_up_id and business_id = p_business_id
    for update;

  if v_follow_up.id is null then
    raise exception 'Follow-up not found in this business';
  end if;

  if v_follow_up.status <> 'PENDING' then
    raise exception 'Only a pending follow-up can be rescheduled';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_assigned_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Assigned staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_assigned_staff_id;

  perform set_config('app.trusted_follow_up_lifecycle_update', 'true', true);
  update follow_ups set
    due_date = p_due_date,
    assigned_staff_id = p_assigned_staff_id,
    assigned_staff_name_snapshot = coalesce(v_staff_name, '')
    where id = p_follow_up_id
    returning * into v_follow_up;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'follow_up', v_follow_up.id, to_jsonb(v_follow_up));

  return v_follow_up;
end;
$$;

revoke execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) from public;
revoke execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) from anon;
grant execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) to authenticated;

--------------------------------------------------------------------------
-- set_follow_up_status: PENDING -> COMPLETED/MISSED/CANCELLED only.
-- completed_at/completed_by are server-set, never client-supplied.
--------------------------------------------------------------------------
create or replace function set_follow_up_status(
  p_business_id uuid,
  p_follow_up_id uuid,
  p_status follow_up_status
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_follow_up follow_ups;
  v_allowed follow_up_status[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to update this follow-up';
  end if;

  select * into v_follow_up from follow_ups
    where id = p_follow_up_id and business_id = p_business_id
    for update;

  if v_follow_up.id is null then
    raise exception 'Follow-up not found in this business';
  end if;

  v_allowed := case v_follow_up.status
    when 'PENDING' then array['COMPLETED', 'MISSED', 'CANCELLED']::follow_up_status[]
    else array[]::follow_up_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move a follow-up from % to %', v_follow_up.status, p_status;
  end if;

  perform set_config('app.trusted_follow_up_lifecycle_update', 'true', true);
  update follow_ups set
    status = p_status,
    completed_at = case when p_status = 'COMPLETED' then now() else completed_at end,
    completed_by = case when p_status = 'COMPLETED' then auth.uid() else completed_by end
    where id = p_follow_up_id
    returning * into v_follow_up;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'follow_up', v_follow_up.id, to_jsonb(v_follow_up));

  return v_follow_up;
end;
$$;

revoke execute on function set_follow_up_status(uuid, uuid, follow_up_status) from public;
revoke execute on function set_follow_up_status(uuid, uuid, follow_up_status) from anon;
grant execute on function set_follow_up_status(uuid, uuid, follow_up_status) to authenticated;

--------------------------------------------------------------------------
-- create_line_link_code: staff-initiated, generates a short-lived 6-digit
-- code the customer sends to the LINE OA to complete linking. The actual
-- link is only ever written by the webhook, never by this function.
--------------------------------------------------------------------------
create or replace function create_line_link_code(
  p_business_id uuid,
  p_customer_id uuid
)
returns customer_line_link_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_code text;
  v_record customer_line_link_codes;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to generate a LINE link code';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  insert into customer_line_link_codes (business_id, customer_id, code, expires_at, created_by)
  values (p_business_id, p_customer_id, v_code, now() + interval '15 minutes', auth.uid())
  returning * into v_record;

  return v_record;
end;
$$;

revoke execute on function create_line_link_code(uuid, uuid) from public;
revoke execute on function create_line_link_code(uuid, uuid) from anon;
grant execute on function create_line_link_code(uuid, uuid) to authenticated;

--------------------------------------------------------------------------
-- unlink_customer_line_account: the only client-facing mutation of
-- customer_line_accounts, and it only ever deletes.
--------------------------------------------------------------------------
create or replace function unlink_customer_line_account(
  p_business_id uuid,
  p_customer_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to unlink a LINE account';
  end if;

  delete from customer_line_accounts
    where business_id = p_business_id and customer_id = p_customer_id;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (
    p_business_id, auth.uid(), 'DELETE', 'customer_line_account', p_customer_id,
    jsonb_build_object('customer_id', p_customer_id)
  );
end;
$$;

revoke execute on function unlink_customer_line_account(uuid, uuid) from public;
revoke execute on function unlink_customer_line_account(uuid, uuid) from anon;
grant execute on function unlink_customer_line_account(uuid, uuid) to authenticated;

--------------------------------------------------------------------------
-- claim_due_follow_up_reminders: service_role only (the reminder-worker
-- Edge Function). Atomically finds newly-eligible follow-ups (PENDING,
-- due within the reminder window, no existing notification row, has a
-- linked LINE account) and claims them by inserting the notification row
-- directly into SENDING -- the INSERT ... ON CONFLICT (follow_up_id) DO
-- NOTHING is the atomicity guarantee: under concurrent execution, only
-- one caller's insert can ever succeed for a given follow_up_id (backed
-- by the UNIQUE constraint), so this function can safely run from
-- overlapping cron invocations with no duplicate-claim window. Customers
-- with no linked LINE account are naturally excluded by the join, not
-- specially handled -- the follow-up itself remains untouched either way.
--------------------------------------------------------------------------
create or replace function claim_due_follow_up_reminders(p_reminder_window_minutes integer default 60)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with eligible as (
    select f.id as follow_up_id, f.business_id, f.customer_id, f.due_date,
           cla.id as customer_line_account_id, cla.line_user_id
    from follow_ups f
    join customer_line_accounts cla
      on cla.business_id = f.business_id and cla.customer_id = f.customer_id
    where f.status = 'PENDING'
      and f.due_date <= now() + (p_reminder_window_minutes || ' minutes')::interval
      and not exists (
        select 1 from follow_up_notifications n where n.follow_up_id = f.id
      )
  ),
  claimed as (
    insert into follow_up_notifications (business_id, follow_up_id, customer_line_account_id, status, claimed_at)
    select e.business_id, e.follow_up_id, e.customer_line_account_id, 'SENDING', now()
    from eligible e
    on conflict (follow_up_id) do nothing
    returning id, follow_up_id, business_id, customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, e.customer_id, c.customer_line_account_id,
         e.line_user_id, e.due_date, b.name
  from claimed c
  join eligible e on e.follow_up_id = c.follow_up_id
  join businesses b on b.id = c.business_id;
end;
$$;

revoke execute on function claim_due_follow_up_reminders(integer) from public;
revoke execute on function claim_due_follow_up_reminders(integer) from anon;
revoke execute on function claim_due_follow_up_reminders(integer) from authenticated;
grant execute on function claim_due_follow_up_reminders(integer) to service_role;

--------------------------------------------------------------------------
-- claim_failed_follow_up_notifications: service_role only. Re-claims
-- previously FAILED notifications for retry, atomically via a plain
-- UPDATE ... WHERE (Postgres row-level locking during the UPDATE is the
-- concurrency guarantee -- the same class of atomic-claim already proven
-- by record_sale_payment's own row locking elsewhere in this project).
-- A follow-up that was completed/missed/cancelled since the failure is
-- correctly excluded (the exists check re-reads current follow_ups.status
-- at claim time), so a stale FAILED row for an obsolete follow-up is
-- never retried.
--------------------------------------------------------------------------
create or replace function claim_failed_follow_up_notifications(p_max_attempts integer default 3)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update follow_up_notifications n set
      status = 'SENDING',
      claimed_at = now()
    where n.status = 'FAILED'
      and n.attempt_count < p_max_attempts
      and exists (
        select 1 from follow_ups f where f.id = n.follow_up_id and f.status = 'PENDING'
      )
    returning n.id, n.follow_up_id, n.business_id, n.customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, f.customer_id, c.customer_line_account_id,
         cla.line_user_id, f.due_date, b.name
  from claimed c
  join follow_ups f on f.id = c.follow_up_id
  join customer_line_accounts cla on cla.id = c.customer_line_account_id
  join businesses b on b.id = c.business_id;
end;
$$;

revoke execute on function claim_failed_follow_up_notifications(integer) from public;
revoke execute on function claim_failed_follow_up_notifications(integer) from anon;
revoke execute on function claim_failed_follow_up_notifications(integer) from authenticated;
grant execute on function claim_failed_follow_up_notifications(integer) to service_role;

--------------------------------------------------------------------------
-- complete_follow_up_notification: service_role only. Marks a claimed
-- (SENDING) notification SENT or FAILED after the actual LINE API call
-- completes. Notification outcome never touches follow_ups itself --
-- satisfies "notification failure must never change the follow-up
-- lifecycle."
--------------------------------------------------------------------------
create or replace function complete_follow_up_notification(
  p_notification_id uuid,
  p_success boolean,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update follow_up_notifications set
    status = case when p_success then 'SENT' else 'FAILED' end,
    sent_at = case when p_success then now() else sent_at end,
    attempt_count = attempt_count + 1,
    last_error = case when p_success then null else p_error end
    where id = p_notification_id and status = 'SENDING';
end;
$$;

revoke execute on function complete_follow_up_notification(uuid, boolean, text) from public;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from anon;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from authenticated;
grant execute on function complete_follow_up_notification(uuid, boolean, text) to service_role;
commit;

begin;
-- Phase 6 remediation (forensic finding MEDIUM-2): a notification claimed
-- into SENDING had no recovery path if the worker crashed/was killed
-- between claim and completion (claim_failed_follow_up_notifications only
-- ever matched status = 'FAILED'), permanently stranding it. This
-- migration adds a bounded stale-claim reclaim, in place, without
-- changing any function's signature, table shape, RLS, or grants.
--
-- Design:
--   - attempt_count now increments at CLAIM time (both the very first
--     claim and every reclaim), not at completion time -- an attempt
--     that never reaches complete_follow_up_notification (a crash) must
--     still count against p_max_attempts, or a persistently-crashing
--     notification could be reclaimed forever. complete_follow_up_notification
--     therefore no longer increments attempt_count itself (moving the
--     increment there again would double-count every attempt that DOES
--     complete normally).
--   - claim_failed_follow_up_notifications' WHERE clause gains a second
--     OR-branch: a SENDING row is reclaimable once its claimed_at is
--     older than a fixed 5-minute staleness threshold. 5 minutes is
--     conservative for this worker's actual shape (one sequential LINE
--     Push API call per claimed row, each normally resolving in low
--     single-digit seconds) while still recovering well within a single
--     pg_cron run cycle (documented as ~15 minutes in
--     supabase/functions/reminder-worker/index.ts's own deployment
--     notes) rather than waiting for the next one.
--   - Both branches remain gated by the SAME atomic UPDATE ... WHERE
--     statement as before -- this is still one plain UPDATE, so Postgres
--     row-level locking is the entire concurrency guarantee: a second
--     concurrent caller's UPDATE on the same row blocks until the first
--     commits, then re-evaluates the WHERE clause against the now-fresh
--     claimed_at/attempt_count the first caller just wrote, and no longer
--     matches. Two workers can never simultaneously believe they own the
--     same notification, and no second notification row is ever created
--     (the unique(follow_up_id) constraint and both claim functions'
--     row-scoped logic are otherwise completely unchanged).
--
-- Explicit, non-hidden limitation (crash-window duplicate-send risk):
--   Worker A claims a notification -> calls the LINE Push API -> LINE
--   accepts and actually delivers the message -> Worker A crashes before
--   it can call complete_follow_up_notification -> the row is still
--   SENDING -> after the staleness threshold elapses, Worker B reclaims
--   the SAME notification and sends AGAIN. This is a real, inherent
--   at-least-once-delivery trade-off, not something this migration (or
--   any purely database-level mechanism) can eliminate -- LINE's own API
--   gives no way to ask "did my last request actually succeed?" after a
--   crash wiped the in-memory result. What this migration guarantees is
--   strictly narrower and is the correct guarantee to claim:
--     - at most one row ever exists per follow_up_id (unchanged)
--     - at most one caller ever holds an active claim on that row at a
--       time (unchanged, still atomic)
--     - a stuck claim is bounded (recovered after ~5 minutes, and overall
--       reclaim attempts remain bounded by p_max_attempts, same as any
--       ordinary FAILED retry)
--   It does NOT and cannot guarantee exactly-once external LINE delivery.
--
-- Residual edge case (documented, not engineered around, per the
-- instruction not to add speculative complexity beyond what was asked):
-- if a notification crashes mid-send on p_max_attempts consecutive
-- reclaims in a row, it stops being reclaimed (attempt_count reaches
-- p_max_attempts) while still sitting in SENDING rather than FAILED.
-- This requires the same single notification to hit the exact crash
-- window multiple times consecutively -- an extremely low-probability
-- compound event -- and is recoverable manually via the notification
-- ledger if it is ever observed. Not addressed here to avoid adding a
-- second bookkeeping mechanism beyond the existing attempt_count/status
-- model for a scenario this unlikely.

create or replace function claim_due_follow_up_reminders(p_reminder_window_minutes integer default 60)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with eligible as (
    select f.id as follow_up_id, f.business_id, f.customer_id, f.due_date,
           cla.id as customer_line_account_id, cla.line_user_id
    from follow_ups f
    join customer_line_accounts cla
      on cla.business_id = f.business_id and cla.customer_id = f.customer_id
    where f.status = 'PENDING'
      and f.due_date <= now() + (p_reminder_window_minutes || ' minutes')::interval
      and not exists (
        select 1 from follow_up_notifications n where n.follow_up_id = f.id
      )
  ),
  claimed as (
    insert into follow_up_notifications (
      business_id, follow_up_id, customer_line_account_id, status, claimed_at, attempt_count
    )
    select e.business_id, e.follow_up_id, e.customer_line_account_id, 'SENDING', now(), 1
    from eligible e
    on conflict (follow_up_id) do nothing
    returning id, follow_up_id, business_id, customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, e.customer_id, c.customer_line_account_id,
         e.line_user_id, e.due_date, b.name
  from claimed c
  join eligible e on e.follow_up_id = c.follow_up_id
  join businesses b on b.id = c.business_id;
end;
$$;

create or replace function claim_failed_follow_up_notifications(p_max_attempts integer default 3)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update follow_up_notifications n set
      status = 'SENDING',
      claimed_at = now(),
      attempt_count = attempt_count + 1
    where n.attempt_count < p_max_attempts
      and (
        n.status = 'FAILED'
        or (n.status = 'SENDING' and n.claimed_at < now() - interval '5 minutes')
      )
      and exists (
        select 1 from follow_ups f where f.id = n.follow_up_id and f.status = 'PENDING'
      )
    returning n.id, n.follow_up_id, n.business_id, n.customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, f.customer_id, c.customer_line_account_id,
         cla.line_user_id, f.due_date, b.name
  from claimed c
  join follow_ups f on f.id = c.follow_up_id
  join customer_line_accounts cla on cla.id = c.customer_line_account_id
  join businesses b on b.id = c.business_id;
end;
$$;

create or replace function complete_follow_up_notification(
  p_notification_id uuid,
  p_success boolean,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update follow_up_notifications set
    status = case when p_success then 'SENT' else 'FAILED' end,
    sent_at = case when p_success then now() else sent_at end,
    last_error = case when p_success then null else p_error end
    where id = p_notification_id and status = 'SENDING';
end;
$$;

-- create or replace function preserves the existing grants (same name,
-- same argument signature for all three functions -- no new overload is
-- created), so no revoke/grant statements are required here. Re-asserted
-- anyway, defensively and idempotently, to leave zero ambiguity that the
-- service_role-only boundary is unchanged by this migration.
revoke execute on function claim_due_follow_up_reminders(integer) from public;
revoke execute on function claim_due_follow_up_reminders(integer) from anon;
revoke execute on function claim_due_follow_up_reminders(integer) from authenticated;
grant execute on function claim_due_follow_up_reminders(integer) to service_role;

revoke execute on function claim_failed_follow_up_notifications(integer) from public;
revoke execute on function claim_failed_follow_up_notifications(integer) from anon;
revoke execute on function claim_failed_follow_up_notifications(integer) from authenticated;
grant execute on function claim_failed_follow_up_notifications(integer) to service_role;

revoke execute on function complete_follow_up_notification(uuid, boolean, text) from public;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from anon;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from authenticated;
grant execute on function complete_follow_up_notification(uuid, boolean, text) to service_role;
commit;

begin;
-- Phase 7 P0 (approved architecture): product/stock integrity, server-side
-- cost RPC, batch_tracked mode flag, and the OPENING_BALANCE enum value.
-- This migration implements ONLY the approved P0 scope -- no batch/receipt
-- tables, no receiving RPC, no FEFO, no stocktake (0052/0053).
--
-- Problem being closed (Phase 7 audit, HIGH finding): products uses direct
-- RLS INSERT/UPDATE/DELETE (0015_rls_policies.sql, MANAGER+) with no column
-- restriction and no protective trigger -- unlike sales/payments/commissions
-- (0022_protect_financial_snapshot_columns.sql) and follow_ups
-- (0049_follow_ups_and_line_oa.sql). ProductRepository.update() sends the
-- full product payload -- including stock_quantity and cost_price -- as a
-- single direct table UPDATE on every edit, silently bypassing
-- inventory_movements entirely (0009's own stated invariant: "nothing
-- should mutate products.stock_quantity without a corresponding row in
-- this table").
--
-- Fix (hybrid, matching the pattern already proven for sales/payments/
-- commissions/follow_ups): catalog fields (name, sku, barcode,
-- description, category_id, supplier_id, active, minimum_stock,
-- selling_price) remain direct-editable by MANAGER+, unchanged.
-- stock_quantity/cost_price/batch_tracked become RPC-only via a new
-- protective trigger, using the same transaction-local trusted-context
-- flag pattern already used four times in this schema (0023
-- customers.total_spent, 0044 sales.paid_amount, 0049 follow_ups
-- lifecycle). selling_price stays direct-editable because sale_items has
-- no UPDATE policy at all (0015) -- unit_price is captured once at sale
-- time and is permanently immutable, so a later selling_price edit can
-- never retroactively misrepresent history, the same justification
-- services.price already relies on elsewhere in this schema.
--
-- batch_tracked is a permanently one-way flag (false -> true only, never
-- reversible even by a trusted caller) establishing whether a product's
-- authoritative stock source is the flat stock_quantity column (false,
-- today's behavior for every existing product -- default) or the batch
-- layer being built in 0052 (true). This migration only adds the column
-- and its protection; nothing in 0051 ever sets it to true -- that first
-- happens in 0052's receive_stock/record_opening_balance_batch RPCs. Every
-- existing product defaults to false, so adjust_stock/complete_sale/
-- void_sale's behavior is byte-for-byte unchanged until 0052 ships and a
-- product actually receives its first batch.
--
-- OPENING_BALANCE is added to inventory_movement_type here, unused, so
-- that 0052 (which will use it in record_opening_balance_batch) never
-- needs to add-and-use the same enum value in one transaction -- the
-- established, hard-learned restriction from 0034/0042 (ALTER TYPE ...
-- ADD VALUE cannot be used in the same transaction that then references
-- it). No table or function in this migration inserts a row using this
-- value.
alter table products add column batch_tracked boolean not null default false;

alter type inventory_movement_type add value 'OPENING_BALANCE';

-- Column protection, two tiers on products (mirrors follow_ups'
-- always-protected vs trusted-flag-gated split):
--   1) batch_tracked: false -> true is trusted-flag-gated (RPC-only,
--      0052's receiving RPCs); true -> false is rejected unconditionally,
--      even with the trusted flag set -- this transition must never be
--      reversible, by design (Phase 7 architecture, Correction 2).
--   2) stock_quantity/cost_price: changeable ONLY via the trusted-context
--      flag set by adjust_stock/complete_sale/void_sale (existing RPCs,
--      updated below) and set_product_cost (new, below). A direct client
--      UPDATE (which can never set this transaction-local flag) can
--      therefore only ever change the remaining catalog columns.
create or replace function protect_products_stock_cost_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.batch_tracked = true and new.batch_tracked = false then
    raise exception 'Cannot revert a product from batch-tracked mode back to unbatched -- this transition is permanent';
  end if;

  if (new.stock_quantity is distinct from old.stock_quantity
      or new.cost_price is distinct from old.cost_price
      or new.batch_tracked is distinct from old.batch_tracked)
     and coalesce(current_setting('app.trusted_product_stock_update', true), '') <> 'true'
  then
    raise exception 'Cannot modify stock quantity, cost price, or batch-tracking mode directly on an existing product -- use adjust_stock, set_product_cost, or the receiving RPCs';
  end if;

  return new;
end;
$$;

create trigger products_protect_stock_cost_columns
  before update on products
  for each row execute function protect_products_stock_cost_columns();

--------------------------------------------------------------------------
-- set_product_cost: narrow, MANAGER+, manual cost-price correction.
-- Separate from receiving (0052) -- receiving captures cost as a natural
-- side effect of a real receipt; this exists so cost correction remains
-- possible immediately, independent of receiving. Writes audit_logs (a
-- business/catalog decision, not a stock-quantity ledger event) --
-- deliberately NOT an inventory_movements row, since no quantity moves.
--------------------------------------------------------------------------
create or replace function set_product_cost(
  p_business_id uuid,
  p_product_id uuid,
  p_cost_price numeric
)
returns products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
  v_old_cost numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to update product cost';
  end if;

  if p_cost_price is null or p_cost_price < 0 then
    raise exception 'Cost price must be zero or greater';
  end if;

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  v_old_cost := v_product.cost_price;

  perform set_config('app.trusted_product_stock_update', 'true', true);
  update products set cost_price = p_cost_price
    where id = p_product_id
    returning * into v_product;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (
    p_business_id, auth.uid(), 'UPDATE', 'product', p_product_id,
    jsonb_build_object('cost_price', v_old_cost),
    jsonb_build_object('cost_price', p_cost_price)
  );

  return v_product;
end;
$$;

revoke execute on function set_product_cost(uuid, uuid, numeric) from public;
revoke execute on function set_product_cost(uuid, uuid, numeric) from anon;
grant execute on function set_product_cost(uuid, uuid, numeric) to authenticated;

--------------------------------------------------------------------------
-- adjust_stock: verbatim from 0020_inventory_stock_adjustment.sql, with
-- exactly one addition -- perform set_config(...) immediately before the
-- stock_quantity UPDATE, required so the new protection trigger above
-- allows this RPC's own write. No other line changed.
--------------------------------------------------------------------------
create or replace function adjust_stock(
  p_business_id uuid,
  p_product_id uuid,
  p_branch_id uuid,
  p_movement_type inventory_movement_type,
  p_quantity_delta integer,
  p_note text
)
returns products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to adjust stock';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity must not be zero';
  end if;

  if p_movement_type = 'SALE' then
    raise exception 'SALE movements can only be recorded by complete_sale';
  end if;

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  if v_product.stock_quantity + p_quantity_delta < 0 then
    raise exception 'Adjustment would take % below zero stock', v_product.name;
  end if;

  perform set_config('app.trusted_product_stock_update', 'true', true);
  update products set stock_quantity = stock_quantity + p_quantity_delta
    where id = p_product_id
    returning * into v_product;

  insert into inventory_movements (
    business_id, branch_id, product_id, movement_type, quantity,
    reference_type, note, created_by
  ) values (
    p_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta,
    'manual_adjustment', p_note, auth.uid()
  );

  return v_product;
end;
$$;

revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from public;
revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from anon;
grant execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) to authenticated;

--------------------------------------------------------------------------
-- complete_sale: verbatim from
-- 0046_complete_sale_authoritative_tax_with_partial_payment.sql (the
-- current live version -- confirmed by inspection, not reconstructed from
-- memory, per the exact lesson that migration's own header documents),
-- with exactly one addition -- perform set_config(...) immediately before
-- the stock_quantity UPDATE inside the product line-item branch. No other
-- line changed. Signature is unchanged (still the same 10 parameters), so
-- this is a plain in-place replace.
--------------------------------------------------------------------------
create or replace function complete_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_items jsonb,
  p_discount_amount numeric,
  p_tax_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text,
  p_allow_partial_payment boolean default false
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_existing sales;
  v_item jsonb;
  v_resolved_items jsonb := '[]'::jsonb;
  v_subtotal numeric(14,2) := 0;
  v_taxable_base numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
  v_sale_item_id uuid;
  v_item_subtotal numeric(14,2);
  v_unit_price numeric(14,2);
  v_service_commission_type commission_kind;
  v_service_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_product_stock integer;
  v_staff_valid boolean;
  v_quantity integer;
  v_discount numeric(14,2);
  v_business businesses;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a sale';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A sale must have at least one item';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_business from businesses where id = p_business_id;

  -- Pass 1: resolve each item's authoritative catalog price exactly once
  -- (never the client-supplied unit_price) and accumulate the sale's
  -- subtotal from those authoritative values.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := coalesce((v_item->>'quantity')::int, 1);
    v_discount := coalesce((v_item->>'discount_amount')::numeric, 0);
    v_service_commission_type := null;
    v_service_commission_value := null;

    if (v_item->>'item_type') = 'SERVICE' then
      select price, commission_type, commission_value
        into v_unit_price, v_service_commission_type, v_service_commission_value
        from services where id = (v_item->>'service_id')::uuid and business_id = p_business_id;

      if v_unit_price is null then
        raise exception 'Service not found in this business';
      end if;
    elsif (v_item->>'item_type') = 'PRODUCT' then
      select selling_price into v_unit_price
        from products where id = (v_item->>'product_id')::uuid and business_id = p_business_id
        for update;

      if v_unit_price is null then
        raise exception 'Product not found in this business';
      end if;
    else
      raise exception 'Invalid item type';
    end if;

    v_item_subtotal := (v_unit_price * v_quantity) - v_discount;
    if v_item_subtotal < 0 then
      raise exception 'Discount cannot exceed the item subtotal';
    end if;

    v_subtotal := v_subtotal + v_item_subtotal;

    v_resolved_items := v_resolved_items || jsonb_build_object(
      'item_type', v_item->>'item_type',
      'service_id', nullif(v_item->>'service_id', ''),
      'product_id', nullif(v_item->>'product_id', ''),
      'staff_id', v_item->>'staff_id',
      'name_snapshot', v_item->>'name_snapshot',
      'quantity', v_quantity,
      'unit_price', v_unit_price,
      'discount_amount', v_discount,
      'item_subtotal', v_item_subtotal,
      'commission_type', v_service_commission_type,
      'commission_value', v_service_commission_value
    );
  end loop;

  if v_subtotal < 0 then
    raise exception 'Invalid sale: subtotal cannot be negative';
  end if;

  -- F9-6-1 (0029): tax is derived authoritatively from the business's own
  -- configuration, never from the client-supplied p_tax_amount (kept in
  -- the signature only for wire compatibility -- unused below).
  v_taxable_base := v_subtotal - coalesce(p_discount_amount, 0);

  if v_business.tax_enabled and v_business.tax_rate > 0 and v_taxable_base > 0 then
    v_tax := round(v_taxable_base * v_business.tax_rate / 100, 2);
  else
    v_tax := 0;
  end if;

  v_total := v_taxable_base + v_tax;
  if v_total < 0 then
    raise exception 'Invalid sale: total cannot be negative';
  end if;

  -- Phase 3 (0043): zero is always rejected; "less than total" is only
  -- rejected when p_allow_partial_payment is not explicitly true.
  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount = 0 then
    raise exception 'Payment amount must be greater than zero';
  elsif p_paid_amount < v_total and not coalesce(p_allow_partial_payment, false) then
    raise exception 'Payment amount cannot be less than the sale total';
  end if;

  v_payment_status := case when p_paid_amount >= v_total then 'COMPLETED' else 'PARTIAL' end;
  v_change := greatest(p_paid_amount - v_total, 0);

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), v_tax, v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  -- Pass 2: persist each line using the already-resolved authoritative
  -- price/subtotal from pass 1 -- no re-query of services/products for
  -- price. Stock sufficiency is still checked and deducted here, in the
  -- same order as before the fix, so two lines referencing the same
  -- product still interact correctly (the lock was already taken in
  -- pass 1, so this re-read is immediate, not blocking).
  for v_item in select * from jsonb_array_elements(v_resolved_items)
  loop
    v_staff_valid := false;
    if (v_item->>'staff_id') is not null then
      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id
          and user_id = (v_item->>'staff_id')::uuid
          and active = true
      );
    end if;

    v_commission_amount := 0;
    if (v_item->>'item_type') = 'SERVICE' and v_staff_valid and (v_item->>'commission_type') is not null then
      if (v_item->>'commission_type') = 'PERCENTAGE' then
        v_commission_amount := round(
          (v_item->>'item_subtotal')::numeric * coalesce((v_item->>'commission_value')::numeric, 0) / 100, 2
        );
      else
        v_commission_amount := coalesce((v_item->>'commission_value')::numeric, 0);
      end if;
    end if;

    insert into sale_items (
      business_id, sale_id, item_type, service_id, product_id, staff_id,
      name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
    ) values (
      p_business_id, v_sale.id, (v_item->>'item_type')::sale_item_kind,
      nullif(v_item->>'service_id', '')::uuid, nullif(v_item->>'product_id', '')::uuid,
      case when v_staff_valid then (v_item->>'staff_id')::uuid else null end,
      v_item->>'name_snapshot', (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric, (v_item->>'discount_amount')::numeric,
      (v_item->>'item_subtotal')::numeric, v_commission_amount
    ) returning id into v_sale_item_id;

    if (v_item->>'item_type') = 'PRODUCT' then
      select stock_quantity into v_product_stock
        from products where id = (v_item->>'product_id')::uuid
        for update;

      if v_product_stock < (v_item->>'quantity')::int then
        raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
      end if;

      perform set_config('app.trusted_product_stock_update', 'true', true);
      update products set stock_quantity = stock_quantity - (v_item->>'quantity')::int
        where id = (v_item->>'product_id')::uuid;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, created_by
      ) values (
        p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
        -(v_item->>'quantity')::int, 'sale', v_sale.id, auth.uid()
      );
    end if;

    if v_commission_amount > 0 and v_staff_valid then
      insert into commissions (
        business_id, sale_id, sale_item_id, staff_id, commission_type,
        commission_rate, commission_amount, status
      ) values (
        p_business_id, v_sale.id, v_sale_item_id, (v_item->>'staff_id')::uuid,
        (v_item->>'commission_type')::commission_kind, coalesce((v_item->>'commission_value')::numeric, 0),
        v_commission_amount, 'PENDING'
      );
    end if;
  end loop;

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, 'COMPLETED', auth.uid());

  if p_customer_id is not null then
    perform set_config('app.trusted_customer_stats_update', 'true', true);
    update customers set
      total_spent = total_spent + v_total,
      visit_count = visit_count + 1,
      last_visit_at = now()
    where id = p_customer_id and business_id = p_business_id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', v_sale.id, to_jsonb(v_sale));

  return v_sale;
end;
$$;

revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text, boolean
) to authenticated;

--------------------------------------------------------------------------
-- void_sale: verbatim from 0045_void_sale_payment_status.sql (the current
-- live version -- confirmed by inspection), with exactly one addition --
-- perform set_config(...) immediately before the stock_quantity UPDATE
-- inside the product-reversal loop. No other line changed. Signature is
-- unchanged, so this is a plain in-place replace.
--------------------------------------------------------------------------
create or replace function void_sale(
  p_business_id uuid,
  p_sale_id uuid,
  p_reason text
)
returns sales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_old_sale jsonb;
  v_item record;
  v_product products;
  v_reversed_commission_count int := 0;
  v_reversed_inventory_count int := 0;
  v_skipped_product_deleted_count int := 0;
  v_customer_package customer_packages;
  v_has_redemptions boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to void a sale';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A void reason is required';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Only a completed sale can be voided';
  end if;

  v_old_sale := to_jsonb(v_sale);

  select * into v_customer_package from customer_packages where sale_id = p_sale_id;

  if v_customer_package.id is not null then
    select exists (
      select 1 from customer_package_items
      where customer_package_id = v_customer_package.id and used_sessions > 0
    ) into v_has_redemptions;

    if v_has_redemptions then
      raise exception 'Cannot void a package sale that has redeemed sessions';
    end if;
  end if;

  for v_item in
    select * from sale_items where sale_id = p_sale_id and item_type = 'PRODUCT'
  loop
    if v_item.product_id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    select * into v_product from products
      where id = v_item.product_id and business_id = p_business_id
      for update;

    if v_product.id is null then
      v_skipped_product_deleted_count := v_skipped_product_deleted_count + 1;
      continue;
    end if;

    perform set_config('app.trusted_product_stock_update', 'true', true);
    update products set stock_quantity = stock_quantity + v_item.quantity
      where id = v_item.product_id;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, reference_id, note, created_by
    ) values (
      p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_item.quantity,
      'sale_void', p_sale_id, 'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
    );

    v_reversed_inventory_count := v_reversed_inventory_count + 1;
  end loop;

  update commissions set status = 'REVERSED'
    where sale_id = p_sale_id and status <> 'REVERSED';
  get diagnostics v_reversed_commission_count = row_count;

  update sales set
    status = 'VOIDED',
    payment_status = 'REFUNDED',
    void_reason = p_reason,
    voided_by = auth.uid(),
    voided_at = now()
    where id = p_sale_id
    returning * into v_sale;

  update payments set status = 'REFUNDED'
    where sale_id = p_sale_id and status <> 'REFUNDED';

  -- Phase 2: cancel the (unused) package entitlement alongside the sale.
  if v_customer_package.id is not null then
    update customer_packages set status = 'CANCELLED' where id = v_customer_package.id;
  end if;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'VOID', 'sale', p_sale_id, v_old_sale, to_jsonb(v_sale),
    jsonb_build_object(
      'reason', p_reason,
      'reversed_commission_count', v_reversed_commission_count,
      'reversed_inventory_line_count', v_reversed_inventory_count,
      'skipped_product_deleted_lines', v_skipped_product_deleted_count,
      'package_cancelled', v_customer_package.id is not null
    )
  );

  return v_sale;
end;
$$;

revoke execute on function void_sale(uuid, uuid, text) from public;
revoke execute on function void_sale(uuid, uuid, text) from anon;
grant execute on function void_sale(uuid, uuid, text) to authenticated;
commit;

begin;
-- Phase 7 P1 (approved architecture): the trusted mechanism that lets a
-- product's existing flat stock_quantity become batch-tracked, and gives
-- 0051's dormant batch_tracked column and OPENING_BALANCE enum value
-- their first real, exercisable code path.
--
-- SCOPE (deliberately narrow -- "implement the smallest production-safe
-- 0052 that matches the approved architecture"): this migration provides
-- ONLY the opening-balance conversion workflow -- the one-time mechanism
-- that lets a product with genuine existing legacy stock become
-- batch-tracked without inventing history. It does NOT include a general
-- "receive new stock" RPC (stock_receipts/receive_stock), does NOT touch
-- complete_sale/void_sale (no FEFO deduction/restoration -- those remain
-- entirely unmodified, confirmed unchanged below), and does NOT add
-- sale_item_batch_allocations or any COGS-snapshot change. Those are
-- separate, later, independently-reviewable migrations. A consequence of
-- this narrow scope, stated plainly rather than hidden: a product that
-- currently has ZERO stock cannot yet be converted to batch_tracked mode
-- in this migration -- there is no receiving RPC yet to give it its first
-- batch from nothing. That capability arrives in a later migration.
--
-- Ledger invariant (unchanged, explicitly preserved): inventory_movements
-- uses signed quantity deltas -- stock IN is positive, stock OUT is
-- negative. OPENING_BALANCE is a stock-establishing IN event, so its
-- quantity is POSITIVE, exactly like PURCHASE/RETURN. This migration does
-- not alter that convention anywhere, and introduces no second sign
-- convention.
--
-- Idempotency: no client-supplied idempotency key is used or needed. The
-- guard is structural: record_opening_balance_batch requires
-- products.batch_tracked = false (checked under a row lock on the
-- product) and flips it to true in the SAME transaction that creates the
-- batch. A retried or concurrent second call either blocks on that same
-- row lock until the first commits (then sees batch_tracked = true and is
-- rejected) or, if called after the first already committed, sees
-- batch_tracked = true immediately. The one-way, irreversible
-- batch_tracked flag (0051's own trigger: true -> false is rejected
-- unconditionally, even with the trusted flag) is therefore reused
-- directly as the one-time-initialization guarantee, rather than
-- inventing a separate mechanism.
--
-- product_batches has no direct-write RLS policy at all (SELECT only) --
-- unlike products (which legitimately needs some direct-write columns and
-- therefore needed 0051's column-level trigger), every column here is
-- RPC-only by construction, so no equivalent protection trigger is
-- needed on this table: RLS with no INSERT/UPDATE/DELETE policy is
-- already a complete block for any non-SECURITY-DEFINER caller.
create table product_batches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  product_id uuid not null references products(id) on delete restrict,
  supplier_id uuid references suppliers(id) on delete set null,
  batch_number text,
  received_at timestamptz not null default now(),
  expiry_date date,
  received_quantity integer not null check (received_quantity > 0),
  remaining_quantity integer not null check (remaining_quantity >= 0 and remaining_quantity <= received_quantity),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- product_id is deliberately ON DELETE RESTRICT, not CASCADE (unlike
-- inventory_movements.product_id, which cascades) -- a batch carries
-- financial data (unit_cost) feeding future valuation/COGS reporting, so
-- hard-deleting a product with received batch history must be blocked;
-- products.active = false is the correct path instead.

create unique index product_batches_business_product_batch_number_key
  on product_batches (business_id, product_id, batch_number)
  where batch_number is not null;

create index product_batches_business_id_idx on product_batches(business_id);
create index product_batches_product_expiry_idx on product_batches(business_id, product_id, expiry_date);

create trigger product_batches_set_updated_at
  before update on product_batches
  for each row execute function set_updated_at();

alter table product_batches enable row level security;

create policy product_batches_select on product_batches
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: every write to this table happens only
-- inside record_opening_balance_batch (below), a SECURITY DEFINER
-- function that bypasses RLS entirely.

-- inventory_movements gains a nullable batch_id, so a movement can be
-- traced to the specific batch it relates to. NULL on every existing
-- (pre-batch-tracking) row -- expected, not an error state; those
-- movements predate batch tracking entirely and are never backfilled.
alter table inventory_movements add column batch_id uuid references product_batches(id) on delete set null;

create index inventory_movements_batch_id_idx on inventory_movements(batch_id);

--------------------------------------------------------------------------
-- record_opening_balance_batch: the one-time, trusted conversion of a
-- product's existing flat stock_quantity into its first batch. Does NOT
-- duplicate or replace set_product_cost (0051) -- p_unit_cost here is the
-- cost basis recorded on the new batch itself (an immutable receipt-shaped
-- fact), a separate concern from products.cost_price (the mutable
-- catalog reference cost, still solely owned by set_product_cost). This
-- function does, as a side effect, set products.batch_tracked -- never
-- products.cost_price.
--------------------------------------------------------------------------
create or replace function record_opening_balance_batch(
  p_business_id uuid,
  p_product_id uuid,
  p_unit_cost numeric,
  p_batch_number text,
  p_expiry_date date
)
returns product_batches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
  v_batch product_batches;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to record an opening balance';
  end if;

  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'Unit cost must be zero or greater';
  end if;

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  -- Structural idempotency / one-time-only guard -- see header comment.
  if v_product.batch_tracked then
    raise exception 'Product is already batch-tracked -- an opening balance can only be recorded once, before batch tracking begins';
  end if;

  if v_product.stock_quantity <= 0 then
    raise exception 'Product has no existing stock to convert into an opening-balance batch';
  end if;

  insert into product_batches (
    business_id, product_id, batch_number, expiry_date,
    received_quantity, remaining_quantity, unit_cost, created_by
  ) values (
    p_business_id, p_product_id, p_batch_number, p_expiry_date,
    v_product.stock_quantity, v_product.stock_quantity, p_unit_cost, auth.uid()
  ) returning * into v_batch;

  -- Deliberately does NOT touch stock_quantity -- it already correctly
  -- holds this exact value (that is the whole point: converting existing
  -- flat stock into batch form must never double-count it). Only
  -- batch_tracked flips, under the same trusted flag 0051 established.
  perform set_config('app.trusted_product_stock_update', 'true', true);
  update products set batch_tracked = true
    where id = p_product_id;

  insert into inventory_movements (
    business_id, product_id, movement_type, quantity, batch_id,
    reference_type, reference_id, created_by
  ) values (
    p_business_id, p_product_id, 'OPENING_BALANCE', v_batch.received_quantity, v_batch.id,
    'opening_balance', v_batch.id, auth.uid()
  );

  -- A consequential, one-time catalog-mode decision (who converted this
  -- product and when) -- distinct in purpose from the inventory_movements
  -- row above (which records the stock fact), matching the same
  -- audit/ledger separation set_product_cost already established in 0051.
  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (
    p_business_id, auth.uid(), 'CREATE', 'opening_balance', v_batch.id,
    jsonb_build_object(
      'product_id', p_product_id,
      'quantity', v_batch.received_quantity,
      'unit_cost', p_unit_cost
    )
  );

  return v_batch;
end;
$$;

revoke execute on function record_opening_balance_batch(uuid, uuid, numeric, text, date) from public;
revoke execute on function record_opening_balance_batch(uuid, uuid, numeric, text, date) from anon;
grant execute on function record_opening_balance_batch(uuid, uuid, numeric, text, date) to authenticated;
commit;

begin;

-- Phase 7 P2 (frozen 0053 design specification): the batch inventory
-- mutation primitives that close the deferred P2 finding from the 0052
-- live verification -- once a product is batch_tracked = true,
-- adjust_stock now becomes batch-aware instead of silently leaving
-- product_batches.remaining_quantity stale.
--
-- SCOPE (deliberately narrow, per the frozen design audit): this
-- migration adds ONLY (1) the sale_item_batch_allocations table (schema
-- only -- nothing in this migration ever writes to it; it exists so a
-- future 0054's batch-aware complete_sale has a table to write into, and
-- so its shape can be independently reviewed now) and (2) a batch-aware
-- rewrite of adjust_stock. It does NOT touch complete_sale, void_sale,
-- FEFO, COGS, receiving, stocktake, branch transfer, or expiry
-- reporting -- all of those remain future, separately-reviewed work.
--
-- Ledger invariant (unchanged, explicitly preserved): inventory_movements
-- remains a signed-delta ledger -- IN positive, OUT negative -- exactly
-- as established in 0009 and reused unmodified by 0051/0052. Nothing in
-- this migration alters that convention.

--------------------------------------------------------------------------
-- Tenant-safe supporting UNIQUE constraints.
--
-- Confirmed by direct inspection during the design audit, not assumed:
-- neither sale_items nor product_batches currently carries a
-- unique(id, business_id) constraint (each has only its bare id PK).
-- Both are required so sale_item_batch_allocations can declare true
-- composite foreign keys -- (child_id, business_id) references
-- (parent.id, parent.business_id) -- rather than two independent
-- single-column FKs, which would allow a sale_item from one business to
-- be paired with a batch from another. Both additions are purely
-- additive and trivially satisfied by every existing row, since id is
-- already the primary key (globally unique) on both tables.
--------------------------------------------------------------------------
alter table sale_items
  add constraint sale_items_id_business_id_key unique (id, business_id);

alter table product_batches
  add constraint product_batches_id_business_id_key unique (id, business_id);

--------------------------------------------------------------------------
-- sale_item_batch_allocations: the permanent, immutable record of which
-- batch(es) funded a sale item. A NULL batch_id represents the future
-- unbatched-sale case (cost drawn from the flat product cost, no
-- specific batch) -- the batch_id FK below is NULL-tolerant by default
-- Postgres MATCH SIMPLE semantics, so such rows are never checked
-- against it.
--
-- No created_by: this is a system-computed historical allocation record,
-- not a standalone staff action -- attribution is already available via
-- sale_item_id -> sale_id -> cashier_id.
--
-- Nothing in THIS migration ever inserts a row here -- that begins only
-- with a future batch-aware complete_sale (0054). The table is
-- introduced now so its shape is independently reviewable ahead of that
-- larger, higher-risk change.
--------------------------------------------------------------------------
create table sale_item_batch_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_item_id uuid not null,
  batch_id uuid,
  quantity integer not null check (quantity > 0),
  unit_cost_snapshot numeric(14,2) not null check (unit_cost_snapshot >= 0),
  created_at timestamptz not null default now(),
  foreign key (sale_item_id, business_id)
    references sale_items(id, business_id) on delete cascade,
  foreign key (batch_id, business_id)
    references product_batches(id, business_id) on delete restrict
);

-- sale_item_id: cascade -- an allocation row has no independent meaning
-- without its parent sale_item (sale_items itself is never hard-deleted
-- in practice, no DELETE RLS policy exists for it, so this is largely
-- theoretical, matching the same reasoning already applied elsewhere in
-- this schema for analogous child records).
-- batch_id: restrict -- mirrors product_batches.product_id's own
-- restrict reasoning; an allocation carries financial data (unit_cost_
-- snapshot) that must not be silently orphaned by a batch deletion (which
-- cannot happen anyway -- product_batches has no delete path at all).

-- Prevents a duplicate row for the same (sale_item, real batch) pair.
alter table sale_item_batch_allocations
  add constraint sale_item_batch_allocations_sale_item_batch_key
  unique (sale_item_id, batch_id);

-- Postgres treats every NULL as distinct under a plain UNIQUE constraint,
-- so the constraint above alone would allow multiple NULL-batch_id rows
-- for the same sale_item_id. This partial unique index closes that gap:
-- at most one NULL-batch allocation per sale item.
create unique index sale_item_batch_allocations_one_null_per_item
  on sale_item_batch_allocations (sale_item_id)
  where batch_id is null;

-- (sale_item_id) alone is deliberately NOT indexed separately: it is
-- already the leading column of both the unique(sale_item_id, batch_id)
-- constraint's index and the partial index above, so a dedicated plain
-- index would be redundant.
create index sale_item_batch_allocations_business_id_idx
  on sale_item_batch_allocations(business_id);
create index sale_item_batch_allocations_batch_id_idx
  on sale_item_batch_allocations(batch_id)
  where batch_id is not null;

alter table sale_item_batch_allocations enable row level security;

create policy sale_item_batch_allocations_select on sale_item_batch_allocations
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy of any kind, and none is granted at the
-- function level either -- no RPC in this migration writes to this
-- table. It is permanently immutable once a future 0054 begins inserting
-- into it: corrections (e.g. a void) are represented by new rows in
-- inventory_movements, never by editing an allocation.

--------------------------------------------------------------------------
-- adjust_stock: recreated in place with an expanded, backward-compatible
-- signature. A new trailing parameter changes this function's type
-- signature, so CREATE OR REPLACE alone would create a second, dangling
-- overload rather than replacing the live one -- the exact same situation
-- 0043_complete_sale_partial_payment.sql already encountered and solved
-- for complete_sale, using DROP FUNCTION IF EXISTS (old signature)
-- immediately before CREATE OR REPLACE FUNCTION (new signature). That
-- proven, precedented technique is reused here verbatim.
--
-- Everything under the "unbatched path" branch below is byte-for-byte
-- identical to the current live function's logic (0051's copy of
-- 0020's body) -- only reorganized into an if/else so it now sits
-- alongside the new batch-aware branch. No unbatched-path behavior
-- changes: any caller supplying only the original six named parameters
-- (p_batch_id defaults to null) gets exactly today's behavior, statement
-- for statement.
--------------------------------------------------------------------------
drop function if exists adjust_stock(
  uuid, uuid, uuid, inventory_movement_type, integer, text
);

create or replace function adjust_stock(
  p_business_id uuid,
  p_product_id uuid,
  p_branch_id uuid,
  p_movement_type inventory_movement_type,
  p_quantity_delta integer,
  p_note text,
  p_batch_id uuid default null
)
returns products
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product products;
  v_batch product_batches;
  v_new_remaining integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to adjust stock';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity must not be zero';
  end if;

  if p_movement_type = 'SALE' then
    raise exception 'SALE movements can only be recorded by complete_sale';
  end if;

  -- Product lock always occurs first, before any batch-related
  -- validation -- binding on every future function that will ever touch
  -- both layers (0054's FEFO walk included).
  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  -- batch_tracked / p_batch_id pairing is symmetric and strict: neither
  -- side may silently disagree with the other. Allowing a supplied
  -- batch_id to be silently ignored on an unbatched product, or allowing
  -- a batch-tracked product to be adjusted without a batch, would
  -- recreate exactly the divergence this migration exists to close.
  if v_product.batch_tracked and p_batch_id is null then
    raise exception 'This product is batch-tracked; a batch must be specified';
  end if;

  if not v_product.batch_tracked and p_batch_id is not null then
    raise exception 'This product is not batch-tracked; do not supply a batch';
  end if;

  if p_batch_id is null then
    -- Unbatched path: unchanged from the pre-0053 live function.
    if v_product.stock_quantity + p_quantity_delta < 0 then
      raise exception 'Adjustment would take % below zero stock', v_product.name;
    end if;

    perform set_config('app.trusted_product_stock_update', 'true', true);
    update products set stock_quantity = stock_quantity + p_quantity_delta
      where id = p_product_id
      returning * into v_product;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, note, created_by
    ) values (
      p_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta,
      'manual_adjustment', p_note, auth.uid()
    );
  else
    -- Batch-aware path.
    select * into v_batch from product_batches
      where id = p_batch_id and business_id = p_business_id and product_id = p_product_id
      for update;

    -- A single generic message covers "doesn't exist," "wrong business,"
    -- and "wrong product" alike -- deliberately not distinguished, so a
    -- caller can never learn whether a given batch_id exists somewhere
    -- just not for them.
    if v_batch.id is null then
      raise exception 'Batch not found for this product in this business';
    end if;

    v_new_remaining := v_batch.remaining_quantity + p_quantity_delta;

    -- received_quantity is a permanent receipt fact and is never altered
    -- here -- only a future, dedicated receiving RPC may ever establish
    -- or increase it, by creating/targeting a batch through its own
    -- explicit workflow. 0053 is not a receiving workflow.
    if p_quantity_delta > 0 and v_new_remaining > v_batch.received_quantity then
      raise exception 'Adjustment would exceed the batch''s received quantity';
    end if;

    if v_new_remaining < 0 then
      raise exception 'Adjustment would take batch % below zero remaining quantity',
        coalesce(v_batch.batch_number, v_batch.id::text);
    end if;

    -- Reaching exactly zero remaining_quantity is a fully valid,
    -- expected state (a completely depleted batch) -- no additional
    -- floor beyond the check above.

    -- The batch's own floor is not, by itself, sufficient: complete_sale
    -- and void_sale (unmodified, out of scope for 0053) still mutate
    -- products.stock_quantity directly for every sale/void of every
    -- product -- including batch_tracked ones -- without ever touching
    -- product_batches.remaining_quantity. That leaves remaining_quantity
    -- free to run stale-high relative to the product's real stock_quantity
    -- the moment a batch-tracked product is sold through the normal POS
    -- flow, which would otherwise let a batch-level-only check approve an
    -- OUT adjustment the product's own CHECK (stock_quantity >= 0)
    -- constraint would then abort with a raw constraint-violation error
    -- instead of this function's own clean, intentional message. Guarding
    -- explicitly here, using the already-locked v_product row, keeps the
    -- rejection inside the function's own error contract regardless of
    -- how far the two figures have drifted apart.
    if v_product.stock_quantity + p_quantity_delta < 0 then
      raise exception 'Adjustment would take % below zero stock', v_product.name;
    end if;

    perform set_config('app.trusted_product_stock_update', 'true', true);
    update products set stock_quantity = stock_quantity + p_quantity_delta
      where id = p_product_id
      returning * into v_product;

    -- product_batches has no direct-write RLS policy at all (0052), so
    -- this UPDATE needs no trusted-flag bypass of its own -- SECURITY
    -- DEFINER alone already grants this function the ability to write
    -- here; the trusted flag above exists solely to satisfy products'
    -- own protective trigger (0051).
    update product_batches set remaining_quantity = v_new_remaining
      where id = p_batch_id;

    insert into inventory_movements (
      business_id, branch_id, product_id, movement_type, quantity,
      reference_type, note, batch_id, created_by
    ) values (
      p_business_id, p_branch_id, p_product_id, p_movement_type, p_quantity_delta,
      'manual_adjustment', p_note, p_batch_id, auth.uid()
    );
  end if;

  return v_product;
end;
$$;

revoke execute on function adjust_stock(
  uuid, uuid, uuid, inventory_movement_type, integer, text, uuid
) from public;
revoke execute on function adjust_stock(
  uuid, uuid, uuid, inventory_movement_type, integer, text, uuid
) from anon;
grant execute on function adjust_stock(
  uuid, uuid, uuid, inventory_movement_type, integer, text, uuid
) to authenticated;
commit;
