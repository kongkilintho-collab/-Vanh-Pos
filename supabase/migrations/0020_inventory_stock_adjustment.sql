-- Manual stock adjustments (restock, correction, damage, expired), keeping
-- products.stock_quantity and inventory_movements consistent atomically --
-- the same problem complete_sale (0017) already solves for the SALE
-- movement type, applied here to the remaining movement types a MANAGER+
-- can record by hand. Without this RPC, a client would need two separate
-- writes (insert inventory_movements, update products.stock_quantity) with
-- no way to guarantee both happen or neither does if the connection drops
-- in between.
--
-- SECURITY DEFINER so it can write across both tables in one transaction,
-- but it re-derives the caller's role itself via
-- has_role_at_least(p_business_id, 'MANAGER') -- the same floor as
-- products_update/inventory_movements_insert RLS -- before doing anything;
-- p_business_id is never trusted purely because the client sent it, and
-- the product row is locked and re-checked against p_business_id so a
-- spoofed product_id from another tenant is rejected, not silently
-- adjusted.
--
-- Learned from 0018/0019: this project's default privileges grant EXECUTE
-- on every newly created public function to anon as a separate ACL entry,
-- independent of PUBLIC -- so anon is revoked explicitly here at creation
-- time instead of needing a follow-up migration.
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
