-- F9-4 (Finalization Phase audit, "Business settings" -- the permission
-- matrix in POS_IMPLEMENTATION_PLAN.md reserves OWNER/ADMIN access for
-- this, and the planned lib/features/settings/ folder was never built).
-- Adds the missing write path for the businesses table's own profile
-- fields (name/phone/email/address/currency/tax_enabled/tax_rate/
-- logo_url), following the exact SECURITY DEFINER RPC + audit + policy-
-- closure pattern already proven twice in this codebase (F9-2's
-- void_sale, F9-3's set_member_role/set_member_active).
--
-- businesses_update (0015_rls_policies.sql) already gates writes to
-- ADMIN+, correctly and with no column restriction needed (unlike sales/
-- payments/commissions, nothing on this table is a computed/snapshot
-- value that a legitimate caller must be prevented from touching -- every
-- column here is exactly what ADMIN+ is meant to edit). But it has never
-- been used by any repository (confirmed by inspection: businesses is
-- only ever read via BusinessRepository.myMemberships()'s join and
-- written via create_business_with_owner's RPC insert -- no direct
-- .update() call exists anywhere in lib/), so it has stood as a live,
-- completely unaudited direct-write bypass since Day 1: any ADMIN+
-- session could already PATCH businesses.tax_rate/currency/name/etc.
-- directly via REST with zero audit_logs row, identical in shape to the
-- sales_update/payments_update/business_members_update bypasses F9-2 and
-- F9-3 closed.
--
-- update_business_settings() replaces that policy as the sole mutation
-- path: SECURITY DEFINER, re-derives the caller's rank server-side via
-- has_role_at_least(p_business_id, 'ADMIN') (never trusts the client),
-- captures the pre-update row, performs the update, and inserts exactly
-- one SETTINGS_CHANGE audit_logs row in the same transaction -- a
-- rejected call (wrong rank, business not found, or a CHECK-constraint
-- violation such as an invalid currency length or an out-of-range
-- tax_rate, both already enforced at the column level since
-- 0002_businesses_branches.sql) raises before reaching the insert, so it
-- can never leave behind a row claiming success.
--
-- businesses_update is dropped once the RPC exists, exactly as
-- sales_update/payments_update/business_members_update were dropped in
-- their respective migrations -- confirmed unused by any other caller
-- first. businesses_select and every other policy on this table are
-- untouched.
--
-- Intended end state:
--   direct authenticated PATCH businesses -> DENIED for every role
--     (0 rows, RLS)
--   update_business_settings -> succeeds for ADMIN+, producing exactly
--     one SETTINGS_CHANGE audit_logs row in the same transaction
--   anon EXECUTE on the new function -> DENIED (42501)
create or replace function update_business_settings(
  p_business_id uuid,
  p_name text,
  p_phone text,
  p_email text,
  p_address text,
  p_currency text,
  p_tax_enabled boolean,
  p_tax_rate numeric,
  p_logo_url text
)
returns businesses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business businesses;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'ADMIN') then
    raise exception 'Insufficient permission to change business settings';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Business name is required';
  end if;

  select * into v_business from businesses where id = p_business_id for update;

  if v_business.id is null then
    raise exception 'Business not found';
  end if;

  v_old_data := to_jsonb(v_business);

  update businesses set
    name = trim(p_name),
    phone = p_phone,
    email = p_email,
    address = p_address,
    currency = p_currency,
    tax_enabled = p_tax_enabled,
    tax_rate = p_tax_rate,
    logo_url = p_logo_url
    where id = p_business_id
    returning * into v_business;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'SETTINGS_CHANGE', 'business', v_business.id, v_old_data, to_jsonb(v_business));

  return v_business;
end;
$$;

revoke execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) from public;
revoke execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) from anon;
grant execute on function update_business_settings(uuid, text, text, text, text, text, boolean, numeric, text) to authenticated;

-- Confirmed unused by any repository (see header) -- close the direct-
-- write bypass now that the RPC covers its legitimate use.
drop policy businesses_update on businesses;
