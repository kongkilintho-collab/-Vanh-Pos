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
