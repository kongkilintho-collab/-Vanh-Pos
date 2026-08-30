-- F9-3 (Finalization Phase audit, "Audit logs wired to every mutation" --
-- POS_IMPLEMENTATION_PLAN.md's own outstanding checklist item). Closes the
-- two remaining sensitive, unaudited write paths and the two direct-write
-- bypasses they created, following the exact pattern F9-2's void_sale
-- established: SECURITY DEFINER RPC + close the direct-write RLS path that
-- would otherwise let a caller skip the audit trail entirely.
--
-- 1) adjust_stock (0020_inventory_stock_adjustment.sql) was already
--    SECURITY DEFINER but never wrote to audit_logs, despite
--    'STOCK_ADJUSTMENT' existing in the audit_action enum since 0001
--    specifically for this. Redeclared here (same signature -- no
--    privilege reset) to capture the product's stock_quantity before/after
--    and log one STOCK_ADJUSTMENT row per successful call, alongside its
--    existing inventory_movements row. No other behavior changes: the same
--    auth.uid()/has_role_at_least('MANAGER') guard, the same
--    quantity/SALE-type/not-found/negative-stock validation, and the same
--    inventory_movements insert, all verbatim from 0020.
--
-- 2) StaffRepository.updateRole/setActive (lib/features/staff/data/
--    staff_repository.dart) were direct `business_members` UPDATEs.
--    business_members_update RLS (0015_rls_policies.sql) already gates
--    these correctly (ADMIN+, and an ADMIN cannot touch or promote to an
--    OWNER/ADMIN row -- only an OWNER can), but a role/active change made
--    through that policy left no audit_logs row at all. Inspected every
--    caller of business_members_update before touching it: only those two
--    StaffRepository methods use it (confirmed via repo-wide grep for
--    `.from('business_members')` -- every other call site is a read).
--
--    set_member_role/set_member_active reproduce the exact same
--    authorization shape as business_members_update's USING/WITH CHECK
--    (also identical in spirit to invite_business_member's own
--    role-escalation guard, already proven correct in this codebase):
--      - caller must be ADMIN+ in the target business
--      - a caller who is not OWNER cannot modify a row that is currently
--        OWNER (mirrors USING's "role <> 'OWNER' or caller is OWNER")
--      - only an OWNER caller may assign OWNER or ADMIN (mirrors WITH
--        CHECK and invite_business_member's own rule) -- this is what
--        makes self- and peer-escalation to OWNER/ADMIN impossible via
--        this path, exactly as it was impossible via the old direct
--        UPDATE
--    guard_last_owner (0016_business_onboarding.sql) is a BEFORE UPDATE
--    trigger, unaffected either way -- it still fires on every UPDATE this
--    RPC performs and still blocks removing/demoting a business's last
--    OWNER regardless of caller.
--
--    Once both RPCs exist, business_members_update is dropped entirely:
--    with StaffRepository migrated to call them instead, no legitimate
--    caller depends on the policy any more, and leaving it in place would
--    let a direct REST PATCH reproduce the same role/active change while
--    skipping the audit_logs insert -- exactly the C1/C2 class of bug F9-2
--    closed for sales/payments. SELECT and the OWNER-row DELETE guard are
--    untouched.
--
-- Intended end state:
--   adjust_stock -> still succeeds exactly as before, plus one
--     STOCK_ADJUSTMENT audit_logs row
--   direct authenticated PATCH business_members (role or active) -> DENIED
--     for every role (0 rows, RLS)
--   set_member_role/set_member_active -> succeed for ADMIN+ (subject to
--     the same OWNER-row/escalation rules as before), each producing
--     exactly one PERMISSION_CHANGE audit_logs row in the same transaction
--   anon EXECUTE on either new function -> DENIED (42501)

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

  select * into v_product from products
    where id = p_product_id and business_id = p_business_id
    for update;

  if v_product.id is null then
    raise exception 'Product not found in this business';
  end if;

  v_before_stock := v_product.stock_quantity;

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

revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from public;
revoke execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) from anon;
grant execute on function adjust_stock(uuid, uuid, uuid, inventory_movement_type, integer, text) to authenticated;

create or replace function set_member_role(
  p_business_id uuid,
  p_target_user_id uuid,
  p_role business_role
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);
  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to change member roles';
  end if;

  select * into v_member from business_members
    where business_id = p_business_id and user_id = p_target_user_id
    for update;

  if v_member.id is null then
    raise exception 'Member not found in this business';
  end if;

  if v_member.role = 'OWNER' and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can modify an owner';
  end if;

  if p_role in ('OWNER', 'ADMIN') and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can assign this role';
  end if;

  v_old_data := to_jsonb(v_member);

  update business_members set role = p_role
    where business_id = p_business_id and user_id = p_target_user_id
    returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, v_old_data, to_jsonb(v_member));

  return v_member;
end;
$$;

revoke execute on function set_member_role(uuid, uuid, business_role) from public;
revoke execute on function set_member_role(uuid, uuid, business_role) from anon;
grant execute on function set_member_role(uuid, uuid, business_role) to authenticated;

create or replace function set_member_active(
  p_business_id uuid,
  p_target_user_id uuid,
  p_active boolean
)
returns business_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_role business_role;
  v_member business_members;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);
  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to change member status';
  end if;

  select * into v_member from business_members
    where business_id = p_business_id and user_id = p_target_user_id
    for update;

  if v_member.id is null then
    raise exception 'Member not found in this business';
  end if;

  if v_member.role = 'OWNER' and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can deactivate or reactivate an owner';
  end if;

  v_old_data := to_jsonb(v_member);

  update business_members set active = p_active
    where business_id = p_business_id and user_id = p_target_user_id
    returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, v_old_data, to_jsonb(v_member));

  return v_member;
end;
$$;

revoke execute on function set_member_active(uuid, uuid, boolean) from public;
revoke execute on function set_member_active(uuid, uuid, boolean) from anon;
grant execute on function set_member_active(uuid, uuid, boolean) to authenticated;

-- Confirmed unused by any other repository (see header) -- close the
-- direct-write bypass now that both RPCs cover its legitimate uses.
drop policy business_members_update on business_members;
