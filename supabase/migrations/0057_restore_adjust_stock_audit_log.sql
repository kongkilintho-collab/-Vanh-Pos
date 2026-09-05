-- F-P10-1 remediation (P2): restores adjust_stock's STOCK_ADJUSTMENT
-- audit_logs entry.
--
-- Root cause: 0027_audit_log_coverage.sql originally added a
-- STOCK_ADJUSTMENT audit_logs insert to adjust_stock. 0051's own header
-- describes its adjust_stock recreation as "verbatim from
-- 0020_inventory_stock_adjustment.sql" -- the pre-0027 body -- so that
-- audit insert was silently dropped at that point, and 0053 (which added
-- batch-aware support) correctly preserved 0051's body byte-for-byte,
-- carrying the gap forward unnoticed. inventory_movements has remained
-- fully intact throughout -- this migration restores only the separate,
-- cross-cutting audit_logs entry 0027 originally added, changing nothing
-- else.
--
-- Signature is unchanged (still the 7-parameter, batch-aware shape from
-- 0053) -- a plain CREATE OR REPLACE is sufficient, no DROP FUNCTION
-- needed, since nothing about the parameter list changes.
--
-- Every line of business logic below -- auth, tenant checks, validation,
-- locking, stock/batch calculations, the trusted-flag mechanism, and both
-- the flat and batch-aware branches -- is byte-for-byte identical to the
-- live 0053 body. Exactly two additions, both minimal:
--   1. v_before_stock is captured once, immediately after the product is
--      locked and confirmed to exist, before either branch runs -- so it
--      reflects the true pre-mutation value regardless of which branch
--      executes.
--   2. One audit_logs insert, placed at the single point both branches
--      already converge on (immediately before `return v_product`), so it
--      fires exactly once per successful call regardless of path, and
--      never fires at all if either branch raises (same transaction,
--      standard rollback). The payload is copied verbatim from 0027's own
--      original semantics -- action='STOCK_ADJUSTMENT', entity_type=
--      'product', entity_id=p_product_id, old_data/new_data carrying only
--      stock_quantity before/after, metadata carrying movement_type/
--      quantity_delta/note -- not redesigned, not extended with batch
--      details.
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
  v_before_stock integer;
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

  v_before_stock := v_product.stock_quantity;

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

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'STOCK_ADJUSTMENT', 'product', p_product_id,
    jsonb_build_object('stock_quantity', v_before_stock),
    jsonb_build_object('stock_quantity', v_product.stock_quantity),
    jsonb_build_object('movement_type', p_movement_type, 'quantity_delta', p_quantity_delta, 'note', p_note)
  );

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
