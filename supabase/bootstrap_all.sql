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


commit;
