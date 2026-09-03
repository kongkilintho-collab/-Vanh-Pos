-- Phase 5: Consultation / Customer Consultation Records.
--
-- A dedicated, separate domain from customer_notes (generic free-text),
-- appointments (booking metadata), treatment_history (what was
-- delivered), and sales (financial transaction) -- following the exact
-- architectural template Phase 4 already established for
-- treatment_history (0047_treatment_history.sql).
--
-- Canonical flow: Customer -> Consultation -> optional Appointment ->
-- Treatment. Every arrow is optional except the first: a consultation
-- never requires a treatment, a treatment never requires a consultation,
-- and a consultation never requires an appointment (walk-in consultation
-- is a required Phase 5 path). Unlike treatment_history, there is no
-- auto-creation path at all -- every consultation is created explicitly,
-- so there is no state-machine hook and no idempotency concern to design
-- for (multiple consultations for the same customer, or even the same
-- appointment, are legitimate business scenarios, not duplicates).
--
-- FK deletion behavior, inspected from the actual existing schema, not
-- guessed:
--   - business_id: on delete cascade (every business-owned table).
--   - customer_id (required, not null): on delete restrict, matching
--     treatment_history.customer_id/customer_packages.customer_id.
--   - appointment_id (optional): on delete set null, matching
--     treatment_history.appointment_id.
--   - staff_id (required, not null): on delete restrict, matching
--     treatment_history.staff_id/appointments.staff_id.
--   - recommended_service_id (optional): on delete set null -- this
--     schema's consistent rule for every OPTIONAL catalog FK (e.g.
--     treatment_history.appointment_id/sale_id), as opposed to the
--     RESTRICT used for REQUIRED catalog FKs like
--     treatment_history.service_id. The recommended_service_name_snapshot
--     column preserves what was actually recommended even after the live
--     service row is gone.
--   - created_by (optional): on delete set null, matching
--     treatment_history.created_by/appointments.created_by.
--
-- Snapshot requirement: staff_name_snapshot is always resolved and stored
-- server-side (required, not null). recommended_service_name_snapshot is
-- resolved server-side only when recommended_service_id is supplied --
-- enforced by a CHECK constraint (both null together, or both non-null
-- together), not merely by RPC discipline, so the invariant holds
-- regardless of write path.
--
-- No idempotency/uniqueness constraint: per the approved Phase 5 scope,
-- multiple consultations for the same customer (or even the same
-- appointment) are legitimate and must not be blocked. This is a
-- deliberate difference from treatment_history's
-- appointment_item_id partial unique index, which exists specifically
-- because that domain has a real duplicate-prevention requirement
-- (one appointment_item -> at most one auto-created record); no
-- equivalent requirement exists here since there is no auto-creation path.
create table consultations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  appointment_id uuid references appointments(id) on delete set null,
  staff_id uuid not null references profiles(id) on delete restrict,
  staff_name_snapshot text not null,
  recommended_service_id uuid references services(id) on delete set null,
  recommended_service_name_snapshot text,
  consultation_date timestamptz not null,
  consultation_notes text,
  customer_concerns text,
  observations text,
  considerations text,
  assessment text,
  recommendation_notes text,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint consultations_recommended_service_snapshot_chk check (
    (recommended_service_id is null and recommended_service_name_snapshot is null)
    or
    (recommended_service_id is not null and recommended_service_name_snapshot is not null)
  )
);

create index consultations_business_id_idx on consultations(business_id);
create index consultations_customer_id_idx
  on consultations(business_id, customer_id, consultation_date desc);
create index consultations_appointment_id_idx on consultations(appointment_id);
create index consultations_staff_id_idx on consultations(staff_id);

create trigger consultations_set_updated_at
  before update on consultations
  for each row execute function set_updated_at();

-- Column protection: only the narrative fields (consultation_notes,
-- customer_concerns, observations, considerations, assessment,
-- recommendation_notes) may be edited on an existing row -- identity/
-- snapshot/attribution fields are permanently fixed at creation, the same
-- BEFORE UPDATE trigger shape already proven for treatment_history (0047)
-- and, before that, sales/payments/commissions (0022). IS DISTINCT FROM
-- means a same-value write is a harmless no-op, not a bypass -- a genuine
-- identity change is what gets rejected.
create or replace function protect_consultation_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.appointment_id is distinct from old.appointment_id
     or new.staff_id is distinct from old.staff_id
     or new.staff_name_snapshot is distinct from old.staff_name_snapshot
     or new.recommended_service_id is distinct from old.recommended_service_id
     or new.recommended_service_name_snapshot is distinct from old.recommended_service_name_snapshot
     or new.consultation_date is distinct from old.consultation_date
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity or snapshot fields on an existing consultation record -- only consultation_notes, customer_concerns, observations, considerations, assessment, and recommendation_notes may be updated';
  end if;
  return new;
end;
$$;

create trigger consultations_protect_identity_columns
  before update on consultations
  for each row execute function protect_consultation_identity_columns();

alter table consultations enable row level security;

create policy consultations_select on consultations
  for select using (is_member(business_id));

-- No direct INSERT policy: creation is exclusively through
-- create_treatment_record's sibling below, create_consultation_record --
-- matching the RPC-only pattern already established for
-- appointments/customer_packages/sales/treatment_history.

create policy consultations_update on consultations
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: consultations are immutable identity/append-only
-- narrative data, matching treatment_history/customer_notes/payments --
-- corrections are narrative edits (still column-protected above), never
-- row removal. No ADMIN delete escape hatch is introduced.

-- create_consultation_record: every identity/snapshot value is resolved
-- and validated server-side from p_business_id-scoped lookups -- the
-- client supplies only ids, the consultation date, and free-text
-- narrative fields, never a name snapshot or a business/tenant claim.
-- Staff is always the explicitly supplied p_staff_id -- an appointment's
-- own staff_id (if any) is never substituted, since a consultation is not
-- an appointment-completion side effect and has no existing project
-- semantics requiring that override.
create or replace function create_consultation_record(
  p_business_id uuid,
  p_customer_id uuid,
  p_staff_id uuid,
  p_consultation_date timestamptz,
  p_appointment_id uuid,
  p_recommended_service_id uuid,
  p_consultation_notes text,
  p_customer_concerns text,
  p_observations text,
  p_considerations text,
  p_assessment text,
  p_recommendation_notes text
)
returns consultations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_staff_valid boolean;
  v_staff_name text;
  v_appointment appointments;
  v_service services;
  v_record consultations;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to record a consultation';
  end if;

  if p_consultation_date is null then
    raise exception 'Consultation date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
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

  if p_recommended_service_id is not null then
    select * into v_service from services
      where id = p_recommended_service_id and business_id = p_business_id;
    if v_service.id is null then
      raise exception 'Recommended service not found in this business';
    end if;
  end if;

  insert into consultations (
    business_id, customer_id, appointment_id, staff_id, staff_name_snapshot,
    recommended_service_id, recommended_service_name_snapshot, consultation_date,
    consultation_notes, customer_concerns, observations, considerations,
    assessment, recommendation_notes, created_by
  ) values (
    p_business_id, p_customer_id, p_appointment_id, p_staff_id, coalesce(v_staff_name, ''),
    p_recommended_service_id,
    case when p_recommended_service_id is not null then v_service.name else null end,
    p_consultation_date,
    p_consultation_notes, p_customer_concerns, p_observations, p_considerations,
    p_assessment, p_recommendation_notes, auth.uid()
  ) returning * into v_record;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'consultation', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) from public;
revoke execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) from anon;
grant execute on function create_consultation_record(
  uuid, uuid, uuid, timestamptz, uuid, uuid, text, text, text, text, text, text
) to authenticated;
