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
