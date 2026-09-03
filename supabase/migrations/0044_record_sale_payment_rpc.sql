-- Phase 3 (Deposit / Outstanding Balance): record_sale_payment -- the
-- authoritative RPC for recording an additional payment against an
-- existing sale and settling (fully or partially) its outstanding balance.
--
-- protect_sales_snapshot_columns (0022) currently blocks ANY change to
-- sales.paid_amount on UPDATE, full stop -- correct at the time, since no
-- legitimate code path ever needed to update an existing sale's paid_amount
-- (complete_sale only ever INSERTs; this trigger fires on UPDATE only, so
-- complete_sale was never affected by it). record_sale_payment is the first
-- legitimate reason to update it, so the trigger gains a narrow,
-- opt-in-by-trusted-context exception -- the exact same pattern already
-- proven safe in 0023_complete_sale_customer_integrity.sql for
-- customers.total_spent/visit_count/last_visit_at: a transaction-local
-- set_config flag that only this RPC sets, immediately before its own
-- UPDATE, inside the same transaction. A client cannot forge this context
-- (set_config is a pg_catalog builtin, never exposed as a PostgREST RPC,
-- and the flag is scoped to this transaction only). Every other blocked
-- column (business_id, branch_id, customer_id, cashier_id, receipt_number,
-- subtotal, discount_amount, tax_amount, total_amount, change_amount,
-- idempotency_key, created_at) is completely untouched -- still
-- unconditionally blocked, exactly as before. payment_status was never
-- blocked by this trigger (it isn't in the original column list), so it
-- needs no special-case handling.
create or replace function protect_sales_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.branch_id is distinct from old.branch_id
     or new.customer_id is distinct from old.customer_id
     or new.cashier_id is distinct from old.cashier_id
     or new.receipt_number is distinct from old.receipt_number
     or new.subtotal is distinct from old.subtotal
     or new.discount_amount is distinct from old.discount_amount
     or new.tax_amount is distinct from old.tax_amount
     or new.total_amount is distinct from old.total_amount
     or new.change_amount is distinct from old.change_amount
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial, attribution, or identity fields on an existing sale -- only status and void metadata may be updated';
  end if;

  if new.paid_amount is distinct from old.paid_amount
     and coalesce(current_setting('app.trusted_sale_settlement_update', true), '') <> 'true'
  then
    raise exception 'Cannot modify paid_amount on an existing sale outside the settlement RPC';
  end if;

  return new;
end;
$$;

-- record_sale_payment: mirrors the auth/role/tenant/locking pattern already
-- proven by void_sale and set_appointment_status. Never trusts a
-- client-supplied balance or paid_amount -- both are recomputed here from
-- the payments table (the append-only source of truth) and the locked
-- sales row, every time.
--
-- Concurrency safety: the sales row is locked FOR UPDATE before the
-- outstanding balance is computed, and held until the new payment is
-- inserted and sales.paid_amount is updated, all in one transaction. Two
-- concurrent calls against the same sale therefore serialize: the second
-- caller blocks on the lock, then (once it resumes) recomputes the
-- outstanding balance from the now-updated payments/sales state, so it can
-- never accept a payment that would push paid_amount past total_amount --
-- there is no window where both calls compute the balance from the same
-- stale snapshot.
create or replace function record_sale_payment(
  p_business_id uuid,
  p_sale_id uuid,
  p_payment_method payment_method_enum,
  p_amount numeric,
  p_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale sales;
  v_payment payments;
  v_paid_amount numeric(14,2);
  v_outstanding numeric(14,2);
  v_new_paid_amount numeric(14,2);
  v_new_outstanding numeric(14,2);
  v_new_payment_status payment_status_enum;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a payment';
  end if;

  select * into v_sale from sales
    where id = p_sale_id and business_id = p_business_id
    for update;

  if v_sale.id is null then
    raise exception 'Sale not found in this business';
  end if;

  if v_sale.status <> 'COMPLETED' then
    raise exception 'Cannot record a payment against a % sale', v_sale.status;
  end if;

  -- Authoritative paid amount: sum of this sale's non-reversed payments,
  -- never the client, never a stale sales.paid_amount snapshot (though in
  -- practice they always agree, since this function is the only writer of
  -- both after the initial complete_sale insert).
  select coalesce(sum(amount), 0) into v_paid_amount
    from payments where sale_id = p_sale_id and status <> 'REFUNDED';

  v_outstanding := v_sale.total_amount - v_paid_amount;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  if v_outstanding <= 0 then
    raise exception 'This sale is already fully paid';
  end if;

  if p_amount > v_outstanding then
    raise exception 'Payment amount cannot exceed the outstanding balance of %', v_outstanding;
  end if;

  insert into payments (business_id, sale_id, payment_method, amount, reference, status, created_by)
  values (p_business_id, p_sale_id, p_payment_method, p_amount, p_reference, 'COMPLETED', auth.uid())
  returning * into v_payment;

  v_new_paid_amount := v_paid_amount + p_amount;
  v_new_outstanding := v_sale.total_amount - v_new_paid_amount;
  v_new_payment_status := case when v_new_outstanding <= 0 then 'COMPLETED' else 'PARTIAL' end;

  perform set_config('app.trusted_sale_settlement_update', 'true', true);
  update sales set
    paid_amount = v_new_paid_amount,
    payment_status = v_new_payment_status
    where id = p_sale_id
    returning * into v_sale;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PAYMENT', 'sale', p_sale_id, to_jsonb(v_payment));

  return jsonb_build_object(
    'payment_id', v_payment.id,
    'payment_amount', v_payment.amount,
    'total_amount', v_sale.total_amount,
    'paid_amount', v_sale.paid_amount,
    'outstanding_balance', greatest(v_new_outstanding, 0),
    'payment_status', v_sale.payment_status
  );
end;
$$;

revoke execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) from public;
revoke execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) from anon;
grant execute on function record_sale_payment(
  uuid, uuid, payment_method_enum, numeric, text
) to authenticated;
