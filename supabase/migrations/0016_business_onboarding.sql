-- Prevents removing or demoting the last remaining OWNER of a business,
-- which would otherwise lock everyone out of admin-level operations.
create or replace function guard_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining_owners int;
begin
  if (tg_op = 'DELETE' and old.role = 'OWNER' and old.active) or
     (tg_op = 'UPDATE' and old.role = 'OWNER' and old.active
        and (new.role <> 'OWNER' or new.active = false)) then
    select count(*) into remaining_owners
    from business_members
    where business_id = old.business_id
      and role = 'OWNER'
      and active = true
      and id <> old.id;

    if remaining_owners = 0 then
      raise exception 'Cannot remove or demote the last owner of a business';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger business_members_guard_last_owner
  before update or delete on business_members
  for each row execute function guard_last_owner();

-- Creates a business and its OWNER membership atomically. This is the only
-- way a business row can come into existence — there is no client-facing
-- INSERT policy on businesses (see 0015_rls_policies.sql) because a
-- membership can't be checked against a business that doesn't exist yet.
create or replace function create_business_with_owner(
  p_name text,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_currency text default 'LAK',
  p_timezone text default 'Asia/Vientiane'
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business businesses;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'Profile not found for current user';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Business name is required';
  end if;

  insert into businesses (name, phone, email, address, currency, timezone)
  values (trim(p_name), p_phone, p_email, p_address,
          coalesce(nullif(p_currency, ''), 'LAK'),
          coalesce(nullif(p_timezone, ''), 'Asia/Vientiane'))
  returning * into v_business;

  insert into business_members (business_id, user_id, role, active)
  values (v_business.id, auth.uid(), 'OWNER', true);

  insert into branches (business_id, name, active)
  values (v_business.id, 'Main Branch', true);

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (v_business.id, auth.uid(), 'CREATE', 'business', v_business.id, to_jsonb(v_business));

  return v_business;
end;
$$;

grant execute on function create_business_with_owner(text, text, text, text, text, text) to authenticated;

-- Adds (or reactivates) a member of an existing business. Role-escalation
-- rules mirror the business_members RLS policies: only an OWNER may grant
-- OWNER or ADMIN.
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

grant execute on function invite_business_member(uuid, uuid, business_role) to authenticated;
