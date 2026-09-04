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
