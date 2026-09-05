-- Phase 9 (frozen design, F-1): a safe, atomic correction mechanism for a
-- completed package redemption -- restores the consumed session, reverses
-- the associated commission (if any), and marks the redemption reversed,
-- without ever touching the appointment's own status (frozen: a completed
-- appointment remains COMPLETED forever; this is an explicit correction
-- against the redemption's side effects, not a new appointment transition).
--
-- Three pieces, all required by the frozen design, in one migration:
--   1. audit_action gains REVERSE_PACKAGE_REDEMPTION (reusing VOID would
--      make this indistinguishable from an actual sale void in any audit
--      query grouped by action).
--   2. protect_commissions_snapshot_columns() (0022) gains one guard:
--      REVERSED is now a database-enforced terminal state for
--      commissions.status, closing a real, previously-unenforced gap --
--      the existing commissions_update RLS policy (0015, ADMIN+) has no
--      column/value restriction at all, and the only thing keeping a
--      REVERSED commission from being moved back to PENDING/APPROVED/PAID
--      today is that the Commissions screen's "next" button never offers
--      it (CommissionStatus.nextInFlow returns null for reversed) --  a
--      UI convention only, trivially bypassed by any direct authenticated
--      write. Extending the existing trigger (not adding a second one) is
--      the same minimal-diff pattern 0044 already used to extend
--      protect_sales_snapshot_columns for paid_amount.
--   3. reverse_package_redemption(), the new RPC itself.
--
-- Enum note: REVERSE_PACKAGE_REDEMPTION is added as its own statement
-- before any function body references it, mirroring
-- 0051_product_stock_cost_integrity.sql's own handling of
-- inventory_movement_type's OPENING_BALANCE addition. A plpgsql function
-- body containing the literal as stored source text (not evaluated until
-- the function is later called, in a separate transaction) is expected to
-- be safe within the same migration transaction unlike, e.g., a plain SQL
-- DEFAULT clause naming the new value -- called out here in case the live
-- SQL Editor apply surfaces Postgres's "unsafe use of new value of enum
-- type" error, in which case the enum ADD VALUE statement below would
-- need to be applied as its own, separately-committed statement first.
alter type audit_action add value 'REVERSE_PACKAGE_REDEMPTION';

--------------------------------------------------------------------------
-- protect_commissions_snapshot_columns: every line above the new
-- paragraph is verbatim from 0022 (unchanged since). The new paragraph
-- makes REVERSED a one-way terminal state -- once set, no UPDATE from any
-- caller (RPC or direct client write alike, since this is a table-level
-- BEFORE UPDATE trigger, independent of RLS) can move status away from
-- REVERSED. REVERSED -> REVERSED (no actual change) is not blocked, since
-- `is distinct from` is false when the value isn't changing.
--------------------------------------------------------------------------
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

  if old.status = 'REVERSED' and new.status is distinct from old.status then
    raise exception 'Cannot change status once a commission has been reversed';
  end if;

  return new;
end;
$$;

--------------------------------------------------------------------------
-- reverse_package_redemption: MANAGER+, tenant-scoped, atomic. Never
-- touches appointments -- the redemption is corrected independently of
-- the (frozen, one-way) appointment state machine.
--
-- Lock order: redemption first (the primary target being corrected,
-- mirroring void_sale locking sales first), then the package item (the
-- session counter), then the commission (lowest contention, a simple
-- status flip) -- last. No table is locked that this operation doesn't
-- actually mutate.
--------------------------------------------------------------------------
create or replace function reverse_package_redemption(
  p_business_id uuid,
  p_redemption_id uuid,
  p_reason text
)
returns customer_package_redemptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_redemption customer_package_redemptions;
  v_old_redemption jsonb;
  v_cpi customer_package_items;
  v_commission commissions;
  v_commission_reversed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'MANAGER') then
    raise exception 'Insufficient permission to reverse a package redemption';
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'A reversal reason is required';
  end if;

  select * into v_redemption from customer_package_redemptions
    where id = p_redemption_id and business_id = p_business_id
    for update;

  if v_redemption.id is null then
    raise exception 'Package redemption not found in this business';
  end if;

  if v_redemption.reversed then
    raise exception 'This package redemption has already been reversed';
  end if;

  v_old_redemption := to_jsonb(v_redemption);

  select * into v_cpi from customer_package_items
    where id = v_redemption.customer_package_item_id and business_id = p_business_id
    for update;

  if v_cpi.id is null then
    raise exception 'Package entitlement not found in this business';
  end if;

  -- Defensive floor check ahead of the UPDATE, mirroring the 0053 P1
  -- lesson: never rely solely on the table's own CHECK (used_sessions >= 0)
  -- for a clean, intentional rejection -- this should never actually be
  -- reachable given an un-reversed redemption implies a prior increment,
  -- but the guard costs nothing and keeps the error contract clean if it
  -- ever is.
  if v_cpi.used_sessions <= 0 then
    raise exception 'Cannot restore a session: no consumed sessions recorded for this package entitlement';
  end if;

  update customer_package_items set used_sessions = used_sessions - 1
    where id = v_cpi.id;

  select * into v_commission from commissions
    where customer_package_redemption_id = v_redemption.id and business_id = p_business_id
    for update;

  if v_commission.id is not null then
    v_commission_reversed := true;
    if v_commission.status <> 'REVERSED' then
      update commissions set status = 'REVERSED' where id = v_commission.id;
    end if;
  end if;

  update customer_package_redemptions set reversed = true
    where id = v_redemption.id
    returning * into v_redemption;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data, metadata)
  values (
    p_business_id, auth.uid(), 'REVERSE_PACKAGE_REDEMPTION', 'customer_package_redemption', v_redemption.id,
    v_old_redemption, to_jsonb(v_redemption),
    jsonb_build_object(
      'reason', p_reason,
      'session_restored', true,
      'commission_reversed', v_commission_reversed
    )
  );

  return v_redemption;
end;
$$;

revoke execute on function reverse_package_redemption(uuid, uuid, text) from public;
revoke execute on function reverse_package_redemption(uuid, uuid, text) from anon;
grant execute on function reverse_package_redemption(uuid, uuid, text) to authenticated;
