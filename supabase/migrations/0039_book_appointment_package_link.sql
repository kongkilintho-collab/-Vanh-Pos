-- Phase 2: book_appointment learns to persist an optional
-- customer_package_item_id per item (0033's new appointment_items column).
-- This does NOT change the function's signature -- p_items is still the
-- same jsonb parameter; unrecognized/absent keys were already ignored, so
-- every existing caller that doesn't send this field is unaffected.
--
-- Booking-time validation here (entitlement belongs to the business, its
-- owning customer_package.customer_id matches p_customer_id, its
-- service_id matches the item's service_id) is a UX nicety only -- it lets
-- an invalid selection be rejected immediately instead of at completion.
-- It is NOT a substitute for the redemption-time re-validation
-- set_appointment_status performs (0037): status/expiry/remaining-sessions
-- can all change between booking and completion, so nothing here is
-- treated as proof that a session may actually be consumed later.
--
-- Every other line is verbatim from 0031_appointment_rpcs.sql.
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
    -- as a UX nicety -- see header.
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
    insert into appointment_items (
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes,
      price_snapshot, customer_package_item_id
    ) values (
      p_business_id, v_appointment.id,
      nullif(v_item->>'service_id', '')::uuid,
      nullif(v_item->>'staff_id', '')::uuid,
      v_item->>'name_snapshot',
      coalesce((v_item->>'duration_minutes')::int, 30),
      coalesce((v_item->>'price_snapshot')::numeric, 0),
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
