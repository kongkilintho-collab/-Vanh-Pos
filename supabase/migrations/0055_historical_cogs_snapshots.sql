-- Phase 8 (frozen design): historical COGS correctness.
--
-- Closes two reporting defects, both entirely pre-existing and independent
-- of batch tracking:
--   F-1: reports_repository.dart's COGS query never checked the parent
--        sale's status, so a VOIDED sale's product cost stayed counted in
--        COGS forever even though its revenue was already correctly
--        excluded.
--   F-2: COGS was computed from products.cost_price -- the product's
--        CURRENT, mutable cost -- rather than any value captured at sale
--        time, for every product line, batch-tracked or not.
--
-- 0053/0054 already solved F-2 for batch-tracked lines
-- (sale_item_batch_allocations.unit_cost_snapshot, immutable, no write
-- policy, no update/delete path). This migration closes the remaining gap
-- for UNBATCHED lines only, going forward -- it adds nowhere near enough
-- information to make historical rows exact (no true historical cost was
-- ever captured for them), and per the frozen design, it must not
-- pretend otherwise: existing rows get NULL, not a fabricated backfill.
-- F-1 itself is a pure query-layer fix (see reports_repository.dart) and
-- needs no schema change at all.

--------------------------------------------------------------------------
-- sale_items.unit_cost_snapshot: the unbatched-line counterpart to
-- sale_item_batch_allocations.unit_cost_snapshot. NULL for every row
-- created before this migration (intentional -- no historical value ever
-- existed for them) and for every SERVICE line (cost is a product-only
-- concept in this reporting model, matching the existing COGS query's
-- item_type='PRODUCT' filter). Populated going forward by complete_sale
-- for unbatched PRODUCT lines only; batch-tracked PRODUCT lines
-- deliberately leave this NULL forever -- their authoritative historical
-- cost is, and remains, the allocation snapshots, never this column, so
-- the two sources can never compete for the same quantity.
--
-- No client write path: sale_items has a SELECT policy and an INSERT
-- policy (0015) but no UPDATE policy at all -- confirmed by direct
-- inspection -- so this column, like every other column on the table, is
-- already fully protected from client mutation by the *absence* of a
-- policy; no new RLS is added or needed. complete_sale's own UPDATE below
-- works via its existing SECURITY DEFINER, exactly like every other
-- protected-column write in this schema.
--------------------------------------------------------------------------
alter table sale_items
  add column unit_cost_snapshot numeric(14,2) check (unit_cost_snapshot is null or unit_cost_snapshot >= 0);

-- No backfill. A prior UPDATE ... SET unit_cost_snapshot = products.cost_price
-- would falsely present today's cost as the historical sale-time cost --
-- exactly what this migration exists to stop doing going forward.

--------------------------------------------------------------------------
-- complete_sale: signature unchanged from 0054 (which itself preserved
-- 0051/0046's signature). Every line is identical to the live 0054 body
-- except one new UPDATE statement in the flat (unbatched) PRODUCT branch,
-- noted below. void_sale is not touched by this migration at all -- it
-- never needs to read or write unit_cost_snapshot, since sale_items rows
-- are never mutated by a void and this column is a permanent, one-time,
-- sale-time fact.
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
  -- subtotal from those authoritative values. Unchanged.
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
  -- price/subtotal from pass 1. The PRODUCT branch below is unchanged
  -- except for the one new UPDATE in the flat sub-branch (marked below).
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
      -- exactly as 0053 requires. Full row needed to read batch_tracked
      -- and (new) cost_price for the historical snapshot below.
      select * into v_product from products
        where id = (v_item->>'product_id')::uuid
        for update;

      if not v_product.batch_tracked then
        -- Flat path: unchanged from 0054 except for one new statement --
        -- capture the product's cost, as locked right now, as this line's
        -- permanent historical cost. Uses the same server-locked v_product
        -- row already read above -- never client input, exactly like
        -- v_unit_price's own resolution in pass 1. Batch-tracked lines
        -- never touch this column; their historical cost is, and remains,
        -- sale_item_batch_allocations.unit_cost_snapshot exclusively, so
        -- the two sources never compete for the same quantity.
        update sale_items set unit_cost_snapshot = v_product.cost_price
          where id = v_sale_item_id;

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
        -- Unchanged from 0054 in every respect.
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
