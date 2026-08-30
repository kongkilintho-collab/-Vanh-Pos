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
