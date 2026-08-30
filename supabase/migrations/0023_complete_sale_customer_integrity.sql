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
