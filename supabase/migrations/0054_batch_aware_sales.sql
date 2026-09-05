-- Phase 7 P3 (frozen 0054 design freeze): batch-aware complete_sale, FEFO
-- allocation, per-batch inventory movements, immutable COGS snapshots, and
-- batch-aware void_sale restoration.
--
-- SCOPE: exactly complete_sale and void_sale, recreated in place with their
-- EXISTING, UNCHANGED signatures (batch selection is entirely server-side
-- FEFO -- the client never supplies a batch_id for a sale, so neither
-- function needs a new parameter). No new RPC, no receiving workflow, no
-- stocktake, no branch transfer, no Flutter/UI change, no modification to
-- 0051/0052/0053.
--
-- Frozen design decisions this migration implements verbatim (see the
-- 0054 design-freeze record):
--   1. Batch<->product integrity is enforced procedurally (the FEFO query's
--      own WHERE clause), not by a schema column on the allocation table.
--   2. One inventory_movements row per batch consumed/restored, never one
--      aggregate row for a batch-tracked line.
--   3. SUM(allocation.quantity) = sale_items.quantity is enforced
--      procedurally inside complete_sale, no trigger, no aggregate CHECK.
--   4. FEFO order: expiry_date asc nulls last, received_at asc, id asc.
--   5. sale_item_batch_allocations is a pure historical ledger -- void
--      never updates/deletes/marks it; sales.status='VOIDED' (already the
--      project's existing reporting convention -- see
--      reports_repository.dart's own sales.status filtering) is the sole
--      void signal.
--   6. products.stock_quantity remains the cache; product_batches rows are
--      the per-batch authority; both move atomically in one transaction.
--   7. Lock order: sale (void only) -> product -> batches in deterministic
--      order, identical across complete_sale, void_sale, and 0053's
--      adjust_stock.

--------------------------------------------------------------------------
-- complete_sale: signature unchanged from
-- 0051_product_stock_cost_integrity.sql (itself verbatim from 0046, plus
-- one trusted-flag line). Pass 1 (authoritative price resolution) is
-- completely unchanged -- it already locks each PRODUCT row `for update`
-- (line ~325 there) before pass 2 runs. Pass 2's PRODUCT branch is the
-- only part rewritten here: it now reads the full product row (needed for
-- batch_tracked) and branches on it.
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
  v_product products;
  v_batch product_batches;
  v_remaining_to_allocate integer;
  v_take integer;
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
  -- subtotal from those authoritative values. Unchanged by 0054.
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
  -- price/subtotal from pass 1. The PRODUCT branch below is the only part
  -- 0054 changes.
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
      -- Product lock first, always -- before any batch is looked at,
      -- exactly as 0053 requires. Full row needed now (not just
      -- stock_quantity) to read batch_tracked.
      select * into v_product from products
        where id = (v_item->>'product_id')::uuid
        for update;

      if not v_product.batch_tracked then
        -- Flat path: byte-for-byte the pre-0054 behavior. batch_id is
        -- omitted from the insert below, so it defaults NULL, and no
        -- sale_item_batch_allocations row is ever created for this line.
        if v_product.stock_quantity < (v_item->>'quantity')::int then
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
      else
        -- Batch-aware path: FEFO allocation across one or more batches.
        -- The `for update` on the ordered query below locks each batch
        -- row, in FEFO order, exactly as it is fetched -- satisfying the
        -- required product-then-batches-in-deterministic-order lock
        -- sequence without a separate locking pass.
        v_remaining_to_allocate := (v_item->>'quantity')::int;

        for v_batch in
          select * from product_batches
            where business_id = p_business_id
              and product_id = (v_item->>'product_id')::uuid
              and remaining_quantity > 0
            order by expiry_date asc nulls last, received_at asc, id asc
            for update
        loop
          exit when v_remaining_to_allocate <= 0;

          v_take := least(v_batch.remaining_quantity, v_remaining_to_allocate);

          update product_batches set remaining_quantity = remaining_quantity - v_take
            where id = v_batch.id;

          insert into sale_item_batch_allocations (
            business_id, sale_item_id, batch_id, quantity, unit_cost_snapshot
          ) values (
            p_business_id, v_sale_item_id, v_batch.id, v_take, v_batch.unit_cost
          );

          insert into inventory_movements (
            business_id, branch_id, product_id, movement_type, quantity,
            reference_type, reference_id, batch_id, created_by
          ) values (
            p_business_id, p_branch_id, (v_item->>'product_id')::uuid, 'SALE',
            -v_take, 'sale', v_sale.id, v_batch.id, auth.uid()
          );

          v_remaining_to_allocate := v_remaining_to_allocate - v_take;
        end loop;

        if v_remaining_to_allocate > 0 then
          raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
        end if;

        -- Defensive product-level floor check, mirroring 0053's own P1
        -- fix in adjust_stock: the FEFO loop above only proves the
        -- eligible batch pool covers the requested quantity, using
        -- product_batches.remaining_quantity as read right now. Nothing
        -- about this migration lets that figure diverge from
        -- products.stock_quantity going forward (both always move
        -- together below), but a product converted to batch-tracked
        -- before this migration existed, or otherwise touched by a path
        -- this migration cannot see, could still carry a stale-high
        -- batch pool relative to its real stock_quantity. Without this
        -- check, that state would let the loop above "succeed" and then
        -- fail on products' own stock_quantity >= 0 CHECK constraint
        -- instead of this function's clean, existing message -- exactly
        -- the failure mode 0053's P1 fix closed for adjust_stock. Same
        -- fix, same reasoning, applied to the highest-traffic path in
        -- the schema.
        if v_product.stock_quantity < (v_item->>'quantity')::int then
          raise exception 'Insufficient stock for %', (v_item->>'name_snapshot');
        end if;

        perform set_config('app.trusted_product_stock_update', 'true', true);
        update products set stock_quantity = stock_quantity - (v_item->>'quantity')::int
          where id = (v_item->>'product_id')::uuid;
      end if;
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
-- void_sale: signature unchanged from 0051 (itself verbatim from 0045,
-- plus one trusted-flag line). The product-restoration UPDATE is
-- unchanged and unconditional (SUM(allocation.quantity) = sale_item.
-- quantity is the frozen invariant complete_sale guarantees, so restoring
-- by v_item.quantity is correct whether or not this line was ever
-- allocated to batches). Only the inventory-movement side of the
-- restoration branches: one aggregate RETURN row (legacy, batch_id NULL)
-- when no allocation rows exist for this sale_item, or one RETURN row per
-- allocation (batch_id set) when they do -- and only in the latter case
-- are the referenced batches' remaining_quantity restored.
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
  v_batch product_batches;
  v_allocation sale_item_batch_allocations;
  v_has_allocations boolean;
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

    -- Unconditional and unchanged: SUM(allocation.quantity) for this line
    -- always equals v_item.quantity by construction at sale time, whether
    -- or not any allocation rows exist, so restoring by v_item.quantity
    -- is correct in both the legacy and batch-aware cases.
    perform set_config('app.trusted_product_stock_update', 'true', true);
    update products set stock_quantity = stock_quantity + v_item.quantity
      where id = v_item.product_id;

    v_has_allocations := false;

    for v_allocation in
      select * from sale_item_batch_allocations
        where sale_item_id = v_item.id
        order by batch_id asc
    loop
      v_has_allocations := true;

      -- Batches have no delete path (product_batches has zero write
      -- policy and no DELETE is ever issued anywhere in this schema), and
      -- the allocation's own composite FK is ON DELETE RESTRICT, so the
      -- referenced batch is guaranteed to still exist -- no existence
      -- check is needed here, unlike the product lookup above.
      select * into v_batch from product_batches
        where id = v_allocation.batch_id and business_id = p_business_id
        for update;

      update product_batches set remaining_quantity = remaining_quantity + v_allocation.quantity
        where id = v_batch.id;

      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, batch_id, note, created_by
      ) values (
        p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_allocation.quantity,
        'sale_void', p_sale_id, v_allocation.batch_id,
        'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
      );
    end loop;

    if not v_has_allocations then
      insert into inventory_movements (
        business_id, branch_id, product_id, movement_type, quantity,
        reference_type, reference_id, note, created_by
      ) values (
        p_business_id, v_sale.branch_id, v_item.product_id, 'RETURN', v_item.quantity,
        'sale_void', p_sale_id, 'Stock reversed from voided sale ' || v_sale.receipt_number, auth.uid()
      );
    end if;

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
