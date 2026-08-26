-- RLS helper functions.
--
-- These are SECURITY DEFINER so they can read business_members without
-- being subject to that table's own RLS policy (which would otherwise
-- recurse: the policy calls is_member(), which queries business_members,
-- which is itself RLS-protected). Each function only ever returns a
-- boolean/role for the CALLING user (auth.uid()) — it never exposes rows
-- the caller shouldn't see, so bypassing RLS internally is safe.
--
-- search_path is pinned to prevent search-path hijacking of a
-- SECURITY DEFINER function.

create or replace function role_rank(p_role business_role)
returns int
language sql
immutable
as $$
  select case p_role
    when 'OWNER' then 5
    when 'ADMIN' then 4
    when 'MANAGER' then 3
    when 'CASHIER' then 2
    when 'STAFF' then 1
  end;
$$;

create or replace function is_member(p_business_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from business_members
    where business_id = p_business_id
      and user_id = auth.uid()
      and active = true
  );
$$;

create or replace function member_role(p_business_id uuid)
returns business_role
language sql
security definer
set search_path = public
stable
as $$
  select role from business_members
  where business_id = p_business_id
    and user_id = auth.uid()
    and active = true
  limit 1;
$$;

create or replace function has_role_at_least(p_business_id uuid, p_min business_role)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(role_rank(member_role(p_business_id)) >= role_rank(p_min), false);
$$;
