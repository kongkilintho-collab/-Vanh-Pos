-- Phase 1: Appointment / Calendar -- write-path RPCs. See
-- 0030_appointments_schema.sql for why appointments/appointment_items have
-- no direct-write RLS policy: these three functions are the only way to
-- create, reschedule, or transition an appointment, exactly like
-- complete_sale/adjust_stock/set_member_role for their own tables.
--
-- All three re-derive the caller's role via has_role_at_least() themselves
-- (never trust p_business_id alone), validate staff_id/customer_id/
-- branch_id/service_id belong to p_business_id (the same style of check
-- complete_sale uses for staff_id/customer_id/service_id/product_id), and
-- rely on appointments_no_staff_overlap (the GIST exclusion constraint) to
-- reject double-bookings -- caught here only to turn a raw
-- "exclusion_violation" Postgres error into a readable message.

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
      business_id, appointment_id, service_id, staff_id, name_snapshot, duration_minutes, price_snapshot
    ) values (
      p_business_id, v_appointment.id,
      nullif(v_item->>'service_id', '')::uuid,
      nullif(v_item->>'staff_id', '')::uuid,
      v_item->>'name_snapshot',
      coalesce((v_item->>'duration_minutes')::int, 30),
      coalesce((v_item->>'price_snapshot')::numeric, 0)
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

-- Status state machine:
--   SCHEDULED  -> CONFIRMED, CANCELLED, NO_SHOW
--   CONFIRMED  -> CHECKED_IN, CANCELLED, NO_SHOW
--   CHECKED_IN -> COMPLETED, CANCELLED
--   COMPLETED / CANCELLED / NO_SHOW -> terminal, no further transitions

create or replace function set_appointment_status(
  p_business_id uuid,
  p_appointment_id uuid,
  p_status appointment_status,
  p_cancel_reason text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
  v_allowed appointment_status[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to change appointment status';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  v_allowed := case v_appointment.status
    when 'SCHEDULED' then array['CONFIRMED', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CONFIRMED' then array['CHECKED_IN', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CHECKED_IN' then array['COMPLETED', 'CANCELLED']::appointment_status[]
    else array[]::appointment_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move an appointment from % to %', v_appointment.status, p_status;
  end if;

  v_old_data := to_jsonb(v_appointment);

  update appointments set
    status = p_status,
    cancel_reason = case when p_status = 'CANCELLED' then p_cancel_reason else cancel_reason end
  where id = p_appointment_id
  returning * into v_appointment;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;

-- Reschedule: only while the appointment is still SCHEDULED/CONFIRMED --
-- once a customer has checked in, moving the time no longer makes sense
-- and should be a cancel + rebook instead.

create or replace function reschedule_appointment(
  p_business_id uuid,
  p_appointment_id uuid,
  p_staff_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to reschedule an appointment';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  if v_appointment.status not in ('SCHEDULED', 'CONFIRMED') then
    raise exception 'Only a scheduled or confirmed appointment can be rescheduled';
  end if;

  if not exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  ) then
    raise exception 'Staff member is not an active member of this business';
  end if;

  v_old_data := to_jsonb(v_appointment);

  begin
    update appointments set
      staff_id = p_staff_id,
      start_at = p_start_at,
      end_at = p_end_at
    where id = p_appointment_id
    returning * into v_appointment;
  exception
    when exclusion_violation then
      raise exception 'This staff member already has a booking that overlaps this time range';
  end;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  return v_appointment;
end;
$$;

revoke execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) from public;
revoke execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) from anon;
grant execute on function reschedule_appointment(uuid, uuid, uuid, timestamptz, timestamptz) to authenticated;
