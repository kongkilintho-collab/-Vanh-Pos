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
