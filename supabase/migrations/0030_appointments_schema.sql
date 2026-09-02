-- Phase 1: Appointment / Calendar.
--
-- Following the pattern complete_sale/adjust_stock/set_member_role already
-- established (and business_members after 0027, which dropped its direct
-- UPDATE policy once its RPCs existed): validated, audited writes go
-- through a SECURITY DEFINER RPC, never a raw client INSERT/UPDATE. So
-- appointments/appointment_items get a SELECT-only RLS policy here; the
-- RPCs in 0031_appointment_rpcs.sql are the only write path.
--
-- One appointment = one staff member, one time block (start_at/end_at),
-- protected against double-booking by a GIST exclusion constraint -- this
-- is enforced by Postgres itself, not application logic, so it holds even
-- under concurrent bookings. An appointment can carry multiple services
-- (appointment_items), each optionally attributed to a different staff
-- member for commission purposes (mirrors sale_items.staff_id), but only
-- the appointment's own staff_id/time range is conflict-checked -- keeping
-- the concurrency-safety story to one exclusion constraint with one clear
-- owner of the booked slot.

create extension if not exists btree_gist;

create type appointment_status as enum (
  'SCHEDULED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED', 'NO_SHOW'
);

create table appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  customer_id uuid references customers(id) on delete set null,
  staff_id uuid not null references profiles(id) on delete restrict,
  start_at timestamptz not null,
  end_at timestamptz not null check (end_at > start_at),
  status appointment_status not null default 'SCHEDULED',
  notes text,
  cancel_reason text,
  sale_id uuid references sales(id) on delete set null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointments_no_staff_overlap exclude using gist (
    staff_id with =,
    tstzrange(start_at, end_at) with &&
  ) where (status in ('SCHEDULED', 'CONFIRMED', 'CHECKED_IN'))
);

create index appointments_business_id_idx on appointments(business_id, start_at);
create index appointments_staff_id_idx on appointments(staff_id, start_at);
create index appointments_customer_id_idx on appointments(customer_id);
create index appointments_branch_id_idx on appointments(branch_id);
create index appointments_status_idx on appointments(business_id, status);

create trigger appointments_set_updated_at
  before update on appointments
  for each row execute function set_updated_at();

create table appointment_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  appointment_id uuid not null references appointments(id) on delete cascade,
  service_id uuid not null references services(id) on delete restrict,
  staff_id uuid references profiles(id) on delete set null,
  name_snapshot text not null,
  duration_minutes integer not null check (duration_minutes > 0),
  price_snapshot numeric(14,2) not null check (price_snapshot >= 0),
  created_at timestamptz not null default now()
);

create index appointment_items_appointment_id_idx on appointment_items(appointment_id);
create index appointment_items_business_id_idx on appointment_items(business_id);
create index appointment_items_service_id_idx on appointment_items(service_id);

alter table appointments enable row level security;
alter table appointment_items enable row level security;

-- SELECT only -- see header. Insert/update happen exclusively through
-- book_appointment/set_appointment_status/reschedule_appointment.

create policy appointments_select on appointments
  for select using (is_member(business_id));

create policy appointment_items_select on appointment_items
  for select using (is_member(business_id));
