-- Phase 4: Customer Treatment History.
--
-- A dedicated, separate service-delivery/history domain -- explicitly NOT
-- merged into sales (financial transaction) or overloaded onto
-- appointments (booking metadata). appointment_id/appointment_item_id/
-- sale_id are optional cross-references only, never a hard dependency:
-- a walk-in customer with no appointment can still get a treatment
-- record via the manual path (create_treatment_record below).
--
-- FK deletion behavior follows this schema's own established conventions,
-- not guessed:
--   - business_id: on delete cascade (every business-owned table).
--   - customer_id (required, not null): on delete restrict, matching
--     customer_packages.customer_id -- the same "required customer FK on a
--     historical/financial-adjacent record" shape.
--   - appointment_id / appointment_item_id / sale_id (all optional):
--     on delete set null, matching customer_packages.sale_id and
--     appointments.customer_id -- a treatment record must survive even if
--     the appointment/sale it references is later removed; it never
--     cascades away.
--   - service_id (required, not null): on delete restrict, matching
--     appointment_items.service_id/package_items.service_id -- the same
--     "required catalog FK, preserved via snapshot + RESTRICT" shape used
--     everywhere else in this schema.
--   - staff_id (required, not null): on delete restrict, matching
--     appointments.staff_id/sales.cashier_id.
--   - created_by (optional): on delete set null, matching
--     appointments.created_by.
--
-- Snapshot requirement: service_name_snapshot/staff_name_snapshot are
-- captured together with their FK at creation time (both RPCs below
-- resolve them server-side, never from client input) -- the snapshot
-- represents what the treatment meant at treatment time and is never
-- rewritten by a later service rename or staff profile change. The FK
-- remains the authoritative live relationship for navigation; the
-- snapshot is display-only history, the same dual pattern already used by
-- appointment_items.name_snapshot, sale_items.name_snapshot, and
-- customer_packages.name_snapshot.
--
-- Idempotency: treatment_history_appointment_item_unique (a partial
-- unique index, not a table-wide constraint -- NULL appointment_item_id
-- rows, i.e. walk-in treatments, are simply not covered by it) is the
-- DB-level guarantee that one appointment_item produces at most one
-- auto-created treatment record, mirroring
-- customer_package_redemptions_appointment_item_unique (0032) exactly.
-- This is defense-in-depth: set_appointment_status's own state machine
-- already makes a second COMPLETED transition on the same appointment
-- structurally impossible (COMPLETED has no outbound transitions), so a
-- true duplicate-invocation race is not actually reachable through the
-- RPC -- the index protects against it regardless, the same way the
-- package-redemption index does for a scenario its own state machine also
-- already prevents.
create table treatment_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete set null,
  appointment_item_id uuid references appointment_items(id) on delete set null,
  sale_id uuid references sales(id) on delete set null,
  service_id uuid not null references services(id) on delete restrict,
  staff_id uuid not null references profiles(id) on delete restrict,
  service_name_snapshot text not null,
  staff_name_snapshot text not null,
  treatment_date timestamptz not null,
  notes text,
  result text,
  customer_feedback text,
  before_after_reference text,
  follow_up_date date,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index treatment_history_business_id_idx on treatment_history(business_id);
create index treatment_history_customer_id_idx
  on treatment_history(business_id, customer_id, treatment_date desc);
create index treatment_history_appointment_id_idx on treatment_history(appointment_id);
create index treatment_history_service_id_idx on treatment_history(service_id);
create index treatment_history_staff_id_idx on treatment_history(staff_id);

create unique index treatment_history_appointment_item_unique
  on treatment_history(appointment_item_id)
  where appointment_item_id is not null;

create trigger treatment_history_set_updated_at
  before update on treatment_history
  for each row execute function set_updated_at();

-- Column protection: only the narrative fields (notes, result,
-- customer_feedback, before_after_reference, follow_up_date) may be
-- edited on an existing row -- identity/snapshot/attribution fields are
-- permanently fixed at creation, the same BEFORE UPDATE trigger shape
-- already proven for sales/payments/commissions (0022).
create or replace function protect_treatment_history_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.appointment_id is distinct from old.appointment_id
     or new.appointment_item_id is distinct from old.appointment_item_id
     or new.sale_id is distinct from old.sale_id
     or new.service_id is distinct from old.service_id
     or new.staff_id is distinct from old.staff_id
     or new.service_name_snapshot is distinct from old.service_name_snapshot
     or new.staff_name_snapshot is distinct from old.staff_name_snapshot
     or new.treatment_date is distinct from old.treatment_date
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity or snapshot fields on an existing treatment record -- only notes, result, customer_feedback, before_after_reference, and follow_up_date may be updated';
  end if;
  return new;
end;
$$;

create trigger treatment_history_protect_identity_columns
  before update on treatment_history
  for each row execute function protect_treatment_history_identity_columns();

alter table treatment_history enable row level security;

create policy treatment_history_select on treatment_history
  for select using (is_member(business_id));

-- No direct INSERT policy: both the auto-creation path
-- (set_appointment_status, below) and the manual/walk-in path
-- (create_treatment_record, below) are SECURITY DEFINER RPCs that resolve
-- and validate every FK/snapshot server-side -- matching the
-- appointments/customer_packages/sales pattern (RPC-only writes for
-- records with server-authoritative derived fields), rather than
-- duplicating write authority between a direct INSERT policy and an RPC.

create policy treatment_history_update on treatment_history
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: treatment history is immutable identity/append-only
-- narrative data, matching customer_notes/payments/inventory_movements --
-- corrections are edits to the narrative fields (still column-protected
-- above), never row removal.

-- create_treatment_record: the manual/walk-in entry path. Every
-- identity/snapshot value is resolved and validated server-side from
-- p_business_id-scoped lookups -- the client supplies only ids, dates,
-- and free-text narrative fields, never a name snapshot or a business/
-- tenant claim.
create or replace function create_treatment_record(
  p_business_id uuid,
  p_customer_id uuid,
  p_service_id uuid,
  p_staff_id uuid,
  p_treatment_date timestamptz,
  p_appointment_id uuid,
  p_appointment_item_id uuid,
  p_sale_id uuid,
  p_notes text,
  p_result text,
  p_customer_feedback text,
  p_before_after_reference text,
  p_follow_up_date date
)
returns treatment_history
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_service services;
  v_staff_valid boolean;
  v_staff_name text;
  v_appointment appointments;
  v_appointment_item appointment_items;
  v_record treatment_history;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a treatment';
  end if;

  if p_treatment_date is null then
    raise exception 'Treatment date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_service from services
    where id = p_service_id and business_id = p_business_id;
  if v_service.id is null then
    raise exception 'Service not found in this business';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_staff_id;

  if p_appointment_id is not null then
    select * into v_appointment from appointments
      where id = p_appointment_id and business_id = p_business_id;
    if v_appointment.id is null then
      raise exception 'Appointment not found in this business';
    end if;
    if v_appointment.customer_id is distinct from p_customer_id then
      raise exception 'This appointment does not belong to the selected customer';
    end if;
  end if;

  if p_appointment_item_id is not null then
    if p_appointment_id is null then
      raise exception 'An appointment item requires its appointment';
    end if;
    select * into v_appointment_item from appointment_items
      where id = p_appointment_item_id
        and appointment_id = p_appointment_id
        and business_id = p_business_id;
    if v_appointment_item.id is null then
      raise exception 'Appointment item not found for this appointment';
    end if;
  end if;

  if p_sale_id is not null and not exists (
    select 1 from sales where id = p_sale_id and business_id = p_business_id
  ) then
    raise exception 'Sale not found in this business';
  end if;

  begin
    insert into treatment_history (
      business_id, customer_id, appointment_id, appointment_item_id, sale_id,
      service_id, staff_id, service_name_snapshot, staff_name_snapshot, treatment_date,
      notes, result, customer_feedback, before_after_reference, follow_up_date, created_by
    ) values (
      p_business_id, p_customer_id, p_appointment_id, p_appointment_item_id, p_sale_id,
      p_service_id, p_staff_id, v_service.name, coalesce(v_staff_name, ''), p_treatment_date,
      p_notes, p_result, p_customer_feedback, p_before_after_reference, p_follow_up_date, auth.uid()
    ) returning * into v_record;
  exception
    when unique_violation then
      raise exception 'A treatment record already exists for this appointment item';
  end;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'treatment_history', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) from public;
revoke execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) from anon;
grant execute on function create_treatment_record(
  uuid, uuid, uuid, uuid, timestamptz, uuid, uuid, uuid, text, text, text, text, date
) to authenticated;

-- set_appointment_status: every line above the "-- Phase 4:" marker is
-- verbatim from 0037_package_rpcs.sql (the current live version) -- auth
-- guard, role check, state machine, the existing status update and its
-- audit_logs insert, and the Phase 2 package-redemption loop are all
-- byte-for-byte unchanged. Only a new loop is appended after the existing
-- package-redemption loop, inside the same `if p_status = 'COMPLETED'`
-- block, so both run in the same transaction as the status transition --
-- any failure anywhere rolls back the whole call, including the status
-- update, so an appointment can never end up COMPLETED with missing
-- treatment history.
--
-- The new loop iterates every appointment_item for the appointment (not
-- just package-linked ones -- treatment history applies to every service
-- delivered, package-covered or not), reusing
-- appointment_items.name_snapshot directly as service_name_snapshot --
-- safe to trust verbatim since P1-01
-- (0041_book_appointment_authoritative_price.sql) made that column
-- server-derived from services.name at booking time, never client-
-- supplied. staff_id falls back to the appointment's own staff_id when an
-- item has none, matching the exact same coalesce already used for
-- commission attribution a few lines below in the existing package loop.
-- A customer-less appointment (p_customer_id was optional at booking) is
-- skipped entirely -- treatment_history.customer_id is NOT NULL, so no
-- treatment record can be created without one; this is expected, not an
-- error.
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
  v_appt_item appointment_items;
  v_cpi customer_package_items;
  v_cp customer_packages;
  v_redemption customer_package_redemptions;
  v_staff_id uuid;
  v_staff_valid boolean;
  v_commission_type commission_kind;
  v_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
  v_staff_name text;
  v_treatment_record treatment_history;
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

  -- Phase 2: completion-time package redemption.
  if p_status = 'COMPLETED' then
    for v_appt_item in
      select * from appointment_items
      where appointment_id = p_appointment_id and customer_package_item_id is not null
    loop
      select * into v_cpi from customer_package_items
        where id = v_appt_item.customer_package_item_id and business_id = p_business_id
        for update;

      if v_cpi.id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      select * into v_cp from customer_packages where id = v_cpi.customer_package_id;

      if v_cp.customer_id is distinct from v_appointment.customer_id then
        raise exception 'This package entitlement does not belong to the appointment''s customer';
      end if;

      if v_cpi.service_id is distinct from v_appt_item.service_id then
        raise exception 'This package entitlement does not cover the booked service';
      end if;

      if v_cp.status <> 'ACTIVE' then
        raise exception 'This package is not active';
      end if;

      if v_cp.expires_at is not null and v_cp.expires_at < now() then
        raise exception 'This package has expired';
      end if;

      if v_cpi.used_sessions >= v_cpi.total_sessions then
        raise exception 'No remaining sessions on this package entitlement';
      end if;

      if exists (
        select 1 from customer_package_redemptions
        where appointment_item_id = v_appt_item.id and not reversed
      ) then
        raise exception 'This service has already been redeemed against a package';
      end if;

      update customer_package_items set used_sessions = used_sessions + 1
        where id = v_cpi.id
        returning * into v_cpi;

      v_staff_id := coalesce(v_appt_item.staff_id, v_appointment.staff_id);

      insert into customer_package_redemptions (
        business_id, customer_package_item_id, appointment_id, appointment_item_id, staff_id
      ) values (
        p_business_id, v_cpi.id, p_appointment_id, v_appt_item.id, v_staff_id
      ) returning * into v_redemption;

      insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
      values (p_business_id, auth.uid(), 'CREATE', 'customer_package_redemption', v_redemption.id, to_jsonb(v_redemption));

      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id and user_id = v_staff_id and active = true
      );

      select commission_type, commission_value into v_commission_type, v_commission_value
        from services where id = v_appt_item.service_id and business_id = p_business_id;

      v_commission_amount := 0;
      if v_staff_valid and v_commission_type is not null then
        if v_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_appt_item.price_snapshot * coalesce(v_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_commission_value, 0);
        end if;
      end if;

      if v_commission_amount > 0 then
        insert into commissions (
          business_id, customer_package_redemption_id, staff_id, commission_type,
          commission_rate, commission_amount, status
        ) values (
          p_business_id, v_redemption.id, v_staff_id,
          v_commission_type, coalesce(v_commission_value, 0), v_commission_amount, 'PENDING'
        );
      end if;
    end loop;

    -- Phase 4: one treatment_history row per appointment item, for every
    -- item (package-linked or not). Skipped entirely for a customer-less
    -- appointment -- see header.
    if v_appointment.customer_id is not null then
      for v_appt_item in
        select * from appointment_items where appointment_id = p_appointment_id
      loop
        select full_name into v_staff_name from profiles
          where id = coalesce(v_appt_item.staff_id, v_appointment.staff_id);

        insert into treatment_history (
          business_id, customer_id, appointment_id, appointment_item_id, sale_id,
          service_id, staff_id, service_name_snapshot, staff_name_snapshot, treatment_date, created_by
        ) values (
          p_business_id, v_appointment.customer_id, p_appointment_id, v_appt_item.id, v_appointment.sale_id,
          v_appt_item.service_id, coalesce(v_appt_item.staff_id, v_appointment.staff_id),
          v_appt_item.name_snapshot, coalesce(v_staff_name, ''), v_appointment.start_at, auth.uid()
        )
        on conflict (appointment_item_id) where appointment_item_id is not null do nothing
        returning * into v_treatment_record;

        if v_treatment_record.id is not null then
          insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
          values (p_business_id, auth.uid(), 'CREATE', 'treatment_history', v_treatment_record.id, to_jsonb(v_treatment_record));
        end if;
      end loop;
    end if;
  end if;

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;
