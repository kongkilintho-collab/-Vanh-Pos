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
