-- Day 6 security audit (F3): create_business_with_owner, invite_business_member,
-- and complete_sale were all created with `grant execute ... to authenticated`
-- but never an explicit `revoke ... from anon` -- the same default-privilege
-- gap 0019 already fixed for find_invitable_user_id and 0020 already avoided
-- for adjust_stock. Confirmed live (empirical anon RPC probe, matching the
-- technique 0019 itself used): all three returned the function's own
-- internal exception (P0001) to an unauthenticated caller instead of
-- Postgres's `42501 permission denied` -- proof anon currently holds
-- EXECUTE on all three.
--
-- This does not change any authorization or business rule already enforced
-- inside these functions -- every legitimate authenticated caller is
-- completely unaffected. It closes the ACL-level backstop so an anonymous
-- caller is rejected by Postgres itself, before the function body (and its
-- internal checks) ever runs, exactly like find_invitable_user_id/
-- adjust_stock already are.
revoke execute on function create_business_with_owner(text, text, text, text, text, text) from public;
revoke execute on function create_business_with_owner(text, text, text, text, text, text) from anon;
grant execute on function create_business_with_owner(text, text, text, text, text, text) to authenticated;

revoke execute on function invite_business_member(uuid, uuid, business_role) from public;
revoke execute on function invite_business_member(uuid, uuid, business_role) from anon;
grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;

revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function complete_sale(
  uuid, uuid, uuid, jsonb, numeric, numeric, payment_method_enum, numeric, text
) to authenticated;

-- F3 also flagged that invite_business_member (unlike create_business_with_owner
-- and complete_sale) has no explicit `auth.uid() is null` guard -- it only
-- rejects an anonymous caller implicitly, because member_role(p_business_id)
-- happens to return null when auth.uid() is null, which then fails the
-- role-rank check below. That is correct today, but it is more fragile than
-- an explicit guard and inconsistent with every other RPC's style. This
-- redeclares the function with the same guard added at the top and every
-- other line identical to 0016's original -- no authorization or business
-- rule changes.
create or replace function invite_business_member(
  p_business_id uuid,
  p_user_id uuid,
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
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  v_caller_role := member_role(p_business_id);

  if v_caller_role is null or role_rank(v_caller_role) < role_rank('ADMIN') then
    raise exception 'Insufficient permission to add members';
  end if;

  if p_role in ('OWNER', 'ADMIN') and v_caller_role <> 'OWNER' then
    raise exception 'Only an owner can assign this role';
  end if;

  if not exists (select 1 from profiles where id = p_user_id) then
    raise exception 'No such user';
  end if;

  insert into business_members (business_id, user_id, role, active)
  values (p_business_id, p_user_id, p_role, true)
  on conflict (business_id, user_id) do update
    set role = excluded.role, active = true
  returning * into v_member;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'PERMISSION_CHANGE', 'business_member', v_member.id, to_jsonb(v_member));

  return v_member;
end;
$$;

-- CREATE OR REPLACE preserves the function's existing GRANT/REVOKE state as
-- long as its signature is unchanged (it is, here), but the grant is
-- restated below for clarity and to be self-contained regardless of
-- migration-application order.
revoke execute on function invite_business_member(uuid, uuid, business_role) from public;
revoke execute on function invite_business_member(uuid, uuid, business_role) from anon;
grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;
