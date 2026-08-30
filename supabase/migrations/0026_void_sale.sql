-- F9-2 (Finalization Phase audit, forensic report dated 2026-08-30): adds
-- the previously-missing void flow (COMPLETED -> VOIDED only; REFUNDED
-- stays deferred -- no partial-refund schema exists, this is scoped
-- exactly as a whole-sale cancellation).
--
-- The audit found that the schema already anticipated this feature --
-- sales.void_reason/voided_by/voided_at and the VOIDED/REFUNDED sale_status
-- values, the VOID/REFUND audit_action values, and commissions.REVERSED
-- have all existed since 0001/0007, unused until now -- so this migration
-- needs no new columns or enum values (movement_type reuses the existing
-- RETURN value; reference_type/reference_id disambiguate a void reversal
-- from a genuine customer return).
--
-- The audit also found two CRITICAL live bypasses, closed here as part of
-- the same change rather than as a follow-up:
--
--   C1: sales_update (0015_rls_policies.sql) let any MANAGER+ PATCH
--   status/void_reason/voided_by/voided_at directly via REST -- the 0022
--   column-protection trigger deliberately allows exactly those columns
--   in anticipation of this feature, but nothing enforced inventory
--   reversal, commission reversal, or an audit record alongside it. No
--   repository in lib/ has ever used this policy (confirmed by inspection
--   before writing this migration), so dropping it costs the app nothing.
--
--   C2: payments_update (0015_rls_policies.sql) let any MANAGER+ PATCH
--   payments.status directly, same unused-by-the-app, same lack of any
--   linkage or audit trail.
--
--   H1: audit_logs_insert (0015_rls_policies.sql) had no role gate at all
--   -- any authenticated business member could insert a fabricated
--   action='VOID' row with arbitrary old_data/new_data, independent of
--   whether a real void ever happened. No repository in lib/ inserts into
--   audit_logs directly (only complete_sale's SECURITY DEFINER insert
--   does, which bypasses RLS anyway and is unaffected by dropping this
--   policy).
--
-- void_sale() follows the exact pattern already proven safe by
-- complete_sale (0024) and adjust_stock (0020): auth.uid() guard,
-- has_role_at_least(p_business_id, 'MANAGER') (role_rank: MANAGER=3,
-- ADMIN=4, OWNER=5 all satisfy this; CASHIER=2/STAFF=1 do not), the target
-- sale is looked up scoped by BOTH id and business_id so a cross-tenant
-- sale_id is indistinguishable from "not found", and the sale row is
-- locked with `for update` before its status is checked -- this is the
-- single serialization point that makes two concurrent void_sale calls on
-- the same sale resolve to exactly one success: the second caller blocks
-- on the lock, then observes status = 'VOIDED' once it resumes and raises
-- before touching inventory/commissions/payments/audit_logs.
--
-- Per-line inventory reversal locks each product row with `for update`
-- (same as adjust_stock/complete_sale) and inserts exactly one
-- inventory_movements row per PRODUCT line with a live product_id.
-- sale_items.product_id can be null if the product was later hard-deleted
-- (products_delete has no dependency check against sale history) -- that
-- line is skipped, not treated as a failure, and the skip is recorded in
-- the audit metadata rather than silently dropped.
--
-- Commission reversal is a single status-only UPDATE (status = 'REVERSED'
-- where not already reversed) -- commission_amount/commission_rate/
-- staff_id/sale_item_id are untouched (also structurally blocked by the
-- 0022 protect_commissions_snapshot_columns trigger, which this bypasses
-- as SECURITY DEFINER but is not fighting: the RPC simply never writes
-- those columns). Reports already exclude REVERSED commissions
-- (reports_repository.dart: .neq('status', 'REVERSED')) and already
-- filter sales/dailyRevenue/salesForRange to status = 'COMPLETED' --
-- neither needs to change.
--
-- Payment reversal is bookkeeping only: payments.status = 'REFUNDED' for
-- the sale's payment row(s); amount/payment_method/reference/created_by
-- are never written by this function, so they remain exactly what was
-- recorded at sale time. No payment-gateway call, no partial-refund
-- amount -- out of scope per the frozen F9-2 design decision.
--
-- The audit_logs insert is the last statement before RETURN, inside the
-- same transaction as every mutation above it -- any failure at any
-- earlier step rolls back the whole transaction, including this insert,
-- so a failed void can never leave behind a record claiming it succeeded.
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

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'VOID', 'sale', p_sale_id, v_old_sale, to_jsonb(v_sale),
    jsonb_build_object(
      'reason', p_reason,
      'reversed_commission_count', v_reversed_commission_count,
      'reversed_inventory_line_count', v_reversed_inventory_count,
      'skipped_product_deleted_lines', v_skipped_product_deleted_count
    )
  );

  return v_sale;
end;
$$;

revoke execute on function void_sale(uuid, uuid, text) from public;
revoke execute on function void_sale(uuid, uuid, text) from anon;
grant execute on function void_sale(uuid, uuid, text) to authenticated;

-- C1/C2/H1: close the live direct-write bypasses now that void_sale is the
-- sole sanctioned path for these transitions. Confirmed unused by any
-- repository in lib/ before dropping. commissions_update is intentionally
-- left untouched -- it is a separate, pre-existing, actively used path
-- (CommissionRepository.updateStatus, ADMIN+) and is outside F9-2 scope.
drop policy sales_update on sales;
drop policy payments_update on payments;
drop policy audit_logs_insert on audit_logs;
