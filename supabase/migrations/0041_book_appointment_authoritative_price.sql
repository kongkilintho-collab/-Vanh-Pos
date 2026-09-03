-- P1-01 fix: book_appointment previously persisted appointment_items.
-- name_snapshot/price_snapshot verbatim from client-supplied p_items, with
-- no re-derivation from services -- the same class of bug F7-1
-- (0024_complete_sale_price_and_payment_integrity.sql) already fixed for
-- complete_sale's unit_price. Phase 2's set_appointment_status (0037) then
-- uses appointment_items.price_snapshot for PERCENTAGE commission
-- calculation on package-redeemed sessions, so an unpatched client-supplied
-- price was directly exploitable for commission manipulation.
--
-- Fix: the second loop (the one that inserts appointment_items) now looks
-- up the service row by the already-validated service_id and writes
-- services.name / services.price as name_snapshot / price_snapshot. The
-- client-supplied 'name_snapshot' and 'price_snapshot' keys in p_items are
-- no longer read at all for these two columns. duration_minutes is
-- untouched (out of P1-01's scope -- not a finding, not a financial value).
--
-- Every other line is verbatim from 0039_book_appointment_package_link.sql:
-- auth guard, role check, staff/customer/branch/service/package-entitlement
-- validation, the double-booking exclusion-violation handler, and the
-- audit_logs insert are all unchanged.
create or replace function book_appointment(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_items jsonb,
  p_notes text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_item jsonb;
  v_service_id uuid;
  v_item_staff_id uuid;
  v_customer_package_item_id uuid;
  v_cpi_customer_id uuid;
  v_cpi_service_id uuid;
  v_service services;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to book an appointment';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'An appointment must have at least one service';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  if p_customer_id is not null and not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  if p_branch_id is not null and not exists (
    select 1 from branches where id = p_branch_id and business_id = p_business_id
  ) then
    raise exception 'Branch not found in this business';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_service_id := nullif(v_item->>'service_id', '')::uuid;
    if v_service_id is null or not exists (
      select 1 from services where id = v_service_id and business_id = p_business_id
    ) then
      raise exception 'Service not found in this business';
    end if;

    v_item_staff_id := nullif(v_item->>'staff_id', '')::uuid;
    if v_item_staff_id is not null and not exists (
      select 1 from business_members
      where business_id = p_business_id and user_id = v_item_staff_id and active = true
    ) then
      raise exception 'Item staff member is not an active member of this business';
    end if;

    -- Phase 2: optional entitlement link, validated at booking time only
    -- as a UX nicety -- see 0039's header.
    v_customer_package_item_id := nullif(v_item->>'customer_package_item_id', '')::uuid;
    if v_customer_package_item_id is not null then
      select cp.customer_id, cpi.service_id into v_cpi_customer_id, v_cpi_service_id
        from customer_package_items cpi
        join customer_packages cp on cp.id = cpi.customer_package_id
        where cpi.id = v_customer_package_item_id and cpi.business_id = p_business_id;

      if v_cpi_customer_id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      if p_customer_id is null or v_cpi_customer_id <> p_customer_id then
        raise exception 'This package entitlement does not belong to the selected customer';
      end if;

      if v_cpi_service_id is distinct from v_service_id then
        raise exception 'This package entitlement does not cover the selected service';
      end if;
    end if;
  end loop;

  begin
    insert into appointments (
      business_id, branch_id, customer_id, staff_id, start_at, end_at, notes, created_by
    ) values (
      p_business_id, p_branch_id, p_customer_id, p_staff_id, p_start_at, p_end_at, p_notes, auth.uid()
    ) returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    -- P1-01 fix: name_snapshot/price_snapshot are derived here from the
    -- services table (already validated above to belong to p_business_id),
    -- never from v_item->>'name_snapshot' / v_item->>'price_snapshot'.
    select * into v_service from services
      where id = nullif(v_item->>'service_id', '')::uuid and business_id = p_business_id;

    insert into appointment_items (
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes,
      price_snapshot, customer_package_item_id
    ) values (
      p_business_id, v_appointment.id,
      v_service.id,
      nullif(v_item->>'staff_id', '')::uuid,
      v_service.name,
      coalesce((v_item->>'duration_minutes')::int, 30),
      v_service.price,
      nullif(v_item->>'customer_package_item_id', '')::uuid
    );
  end loop;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'appointment', v_appointment.id, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from public;
revoke execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) from anon;
grant execute on function book_appointment(
  uuid, uuid, uuid, uuid, timestamptz, timestamptz, jsonb, text
) to authenticated;
