-- Resolves an email address to a user_id so an ADMIN+ can invite an
-- existing account into their business via invite_business_member(),
-- which requires a user_id -- profiles carries no email column (email
-- lives only in auth.users), so without this there is no client-safe way
-- to turn "invite this email" into the user_id that RPC needs.
--
-- Deliberately NOT a general "find user by email" API:
--   - the caller must already be ADMIN+ of the SPECIFIC business they're
--     inviting into (p_business_id is a required, checked parameter, not
--     merely "some business" the caller happens to belong to);
--   - the only thing ever returned is a bare uuid or null -- never email,
--     name, phone, or any other auth.users field;
--   - unauthenticated/insufficiently-privileged callers are rejected via
--     the same has_role_at_least() check every other write path in this
--     schema uses, so auth.uid() being null or the caller lacking ADMIN+
--     both fail closed the same way invite_business_member() itself does.
--
-- Accepted, explicit tradeoff: an ADMIN can still learn "an account with
-- this email exists" for an email they try -- that is the inherent
-- minimum disclosure of any invite-by-email flow and is bounded to
-- authenticated ADMIN-tier members of a real business, not any caller.
create or replace function find_invitable_user_id(p_business_id uuid, p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_user_id uuid;
begin
  if not has_role_at_least(p_business_id, 'ADMIN') then
    raise exception 'Insufficient permission to look up invitable users';
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(trim(coalesce(p_email, '')))
  limit 1;

  return v_user_id;
end;
$$;

revoke execute on function find_invitable_user_id(uuid, text) from public;
grant execute on function find_invitable_user_id(uuid, text) to authenticated;
