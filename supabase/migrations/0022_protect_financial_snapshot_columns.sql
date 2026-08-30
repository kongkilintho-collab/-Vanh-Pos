-- Day 6 security audit (F1): sales_update, payments_update, and
-- commissions_update (0015_rls_policies.sql) correctly gate WHO may update
-- a row (MANAGER+/ADMIN+), but RLS is row-level, not column-level -- none
-- of the three policies restrict WHICH columns a permitted caller may
-- change. That means a MANAGER+/ADMIN+ session used directly against the
-- REST API (not through this app, which never does this -- confirmed no
-- repository performs such an update) could rewrite total_amount,
-- paid_amount, commission_amount, staff attribution, or even
-- idempotency_key on an existing row, bypassing every guarantee
-- complete_sale established at creation time.
--
-- This does not touch the RLS policies themselves (no policy is weakened
-- or replaced) and does not touch complete_sale, since complete_sale only
-- ever INSERTs into these three tables, never UPDATEs an existing row --
-- confirmed by inspection of 0017_pos_checkout.sql. These triggers fire on
-- UPDATE only, so the Day 2 checkout path is entirely unaffected.
--
-- Each trigger blocks changes to the server-computed/snapshot/attribution
-- columns and explicitly allows the columns that represent a legitimate
-- status/void-metadata transition (the model this project's own plan
-- describes for the not-yet-built void_sale flow: "status update +
-- inventory reversal + commission reversal + audit log", i.e. state
-- transitions on existing rows, not raw field edits). This does not
-- implement or design that refund/void workflow -- it only ensures that
-- whenever it lands, it (and today's role-gated status changes) can still
-- update `status`/void metadata while financial history stays immutable.

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
     or new.paid_amount is distinct from old.paid_amount
     or new.change_amount is distinct from old.change_amount
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial, attribution, or identity fields on an existing sale -- only status and void metadata may be updated';
  end if;
  return new;
end;
$$;

create trigger sales_protect_snapshot_columns
  before update on sales
  for each row execute function protect_sales_snapshot_columns();

create or replace function protect_payments_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.sale_id is distinct from old.sale_id
     or new.payment_method is distinct from old.payment_method
     or new.amount is distinct from old.amount
     or new.reference is distinct from old.reference
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify financial or identity fields on an existing payment -- only status may be updated';
  end if;
  return new;
end;
$$;

create trigger payments_protect_snapshot_columns
  before update on payments
  for each row execute function protect_payments_snapshot_columns();

create or replace function protect_commissions_snapshot_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.sale_id is distinct from old.sale_id
     or new.sale_item_id is distinct from old.sale_item_id
     or new.staff_id is distinct from old.staff_id
     or new.commission_type is distinct from old.commission_type
     or new.commission_rate is distinct from old.commission_rate
     or new.commission_amount is distinct from old.commission_amount
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify commission amount, rate, or attribution on an existing commission -- only status may be updated';
  end if;
  return new;
end;
$$;

create trigger commissions_protect_snapshot_columns
  before update on commissions
  for each row execute function protect_commissions_snapshot_columns();
