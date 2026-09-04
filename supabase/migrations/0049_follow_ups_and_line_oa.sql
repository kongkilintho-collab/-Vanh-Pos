-- Phase 6: Follow-up / Reminder + LINE OA integration.
--
-- Five new tables, following the exact architectural template Phase 4/5
-- established: dedicated domains, snapshot+FK pattern, RPC-only writes
-- for anything server-authoritative, narrative-only direct-RLS UPDATE
-- where applicable, no DELETE policy on historical records.
--
-- follow_ups: staff-managed customer follow-up records. DUE/OVERDUE are
-- explicitly NOT stored -- they are always derived from
-- (status = 'PENDING' and due_date compared to now()), computed at query
-- time, avoiding any cron-driven state-flipping and any possibility of
-- stored state disagreeing with reality.
--
-- customer_line_accounts: the trusted LINE user <-> customer link.
-- Never written by the client -- only by the signature-verified webhook
-- Edge Function (via the service_role key, which bypasses RLS) or by the
-- unlink_customer_line_account RPC below (delete only, no client-supplied
-- line_user_id is ever accepted anywhere in this migration).
--
-- customer_line_link_codes: a short-lived, single-use, staff-generated
-- code that correlates a specific (business_id, customer_id) to whatever
-- LINE account later sends that code to the OA. This is the mechanism
-- that lets the webhook trust the eventual line_user_id it receives
-- directly from LINE's own signed payload, while still tying it to the
-- correct tenant/customer -- Flutter never supplies or sees a line_user_id
-- anywhere in this flow.
--
-- follow_up_notifications: the reminder delivery ledger. UNIQUE on
-- follow_up_id enforces "one reminder per follow-up" at the database
-- level. claim_due_follow_up_reminders/claim_failed_follow_up_notifications
-- (both service_role-only) are the atomic-claim mechanism -- the INSERT
-- ... ON CONFLICT DO NOTHING / UPDATE ... WHERE status = ... are
-- themselves the concurrency-safety guarantee (no "check then send"
-- window exists), the same class of technique already proven in this
-- project by record_sale_payment/void_sale's row-locking.
--
-- FK deletion behavior, inspected from actual existing precedent, not
-- guessed:
--   - business_id: on delete cascade everywhere (every business-owned table).
--   - follow_ups.customer_id/assigned_staff_id (required): restrict,
--     matching treatment_history/consultations' own required-FK shape.
--   - follow_ups.consultation_id/treatment_history_id/appointment_id/
--     created_by/completed_by (all optional): set null, matching
--     consultations' own optional-cross-reference shape.
--   - customer_line_accounts.customer_id: cascade -- unlike follow_ups/
--     treatment_history/consultations, this table has no historical-
--     record semantics worth preserving after a customer is deleted; it
--     is pure operational linkage metadata.
--   - customer_line_link_codes.customer_id: cascade, same reasoning.
--   - follow_up_notifications.follow_up_id: cascade -- a notification
--     ledger row has no independent meaning without its parent follow-up.
--   - follow_up_notifications.customer_line_account_id: set null --
--     preserves the delivery-attempt record even if the link is later
--     removed.
create type follow_up_status as enum ('PENDING', 'COMPLETED', 'MISSED', 'CANCELLED');
create type follow_up_notification_status as enum ('PENDING', 'SENDING', 'SENT', 'FAILED');

create table follow_ups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete restrict,
  assigned_staff_id uuid not null references profiles(id) on delete restrict,
  assigned_staff_name_snapshot text not null,
  consultation_id uuid references consultations(id) on delete set null,
  treatment_history_id uuid references treatment_history(id) on delete set null,
  appointment_id uuid references appointments(id) on delete set null,
  due_date timestamptz not null,
  status follow_up_status not null default 'PENDING',
  follow_up_notes text,
  completed_at timestamptz,
  completed_by uuid references profiles(id) on delete set null,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index follow_ups_customer_idx on follow_ups(business_id, customer_id, due_date);
create index follow_ups_status_due_idx on follow_ups(business_id, status, due_date);
create index follow_ups_assigned_staff_idx on follow_ups(assigned_staff_id);

create trigger follow_ups_set_updated_at
  before update on follow_ups
  for each row execute function set_updated_at();

-- Column protection, two tiers:
--   1) Permanently fixed, never changeable by anyone, any path:
--      business_id, customer_id, consultation_id, treatment_history_id,
--      appointment_id, created_by, created_at.
--   2) Lifecycle fields (assigned_staff_id/assigned_staff_name_snapshot/
--      due_date/status/completed_at/completed_by): changeable ONLY via
--      the trusted-context flag set by reschedule_follow_up/
--      set_follow_up_status below -- the same set_config/current_setting
--      pattern already proven for sales.paid_amount (0044) and
--      customers.total_spent (0023). A direct client UPDATE (which can
--      never set this transaction-local flag) can therefore only ever
--      change follow_up_notes.
create or replace function protect_follow_up_identity_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.business_id is distinct from old.business_id
     or new.customer_id is distinct from old.customer_id
     or new.consultation_id is distinct from old.consultation_id
     or new.treatment_history_id is distinct from old.treatment_history_id
     or new.appointment_id is distinct from old.appointment_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Cannot modify identity fields on an existing follow-up';
  end if;

  if (new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.assigned_staff_name_snapshot is distinct from old.assigned_staff_name_snapshot
      or new.due_date is distinct from old.due_date
      or new.status is distinct from old.status
      or new.completed_at is distinct from old.completed_at
      or new.completed_by is distinct from old.completed_by)
     and coalesce(current_setting('app.trusted_follow_up_lifecycle_update', true), '') <> 'true'
  then
    raise exception 'Cannot modify assigned staff, due date, status, or completion fields on an existing follow-up outside the reschedule/status-transition RPCs -- only follow_up_notes may be updated directly';
  end if;

  return new;
end;
$$;

create trigger follow_ups_protect_identity_columns
  before update on follow_ups
  for each row execute function protect_follow_up_identity_columns();

alter table follow_ups enable row level security;

create policy follow_ups_select on follow_ups
  for select using (is_member(business_id));

-- No direct INSERT policy: creation is exclusively through
-- create_follow_up below.

create policy follow_ups_update on follow_ups
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

-- No DELETE policy: follow-ups are immutable identity/append-only data,
-- matching treatment_history/consultations -- corrections are status
-- transitions (CANCELLED), never row removal.

-- customer_line_accounts: never written by any client-facing RPC with a
-- client-supplied line_user_id. Only the webhook Edge Function (service_role,
-- bypasses RLS) writes new links, resolving line_user_id exclusively from
-- LINE's own signed webhook payload. unlink_customer_line_account below is
-- the only client-facing mutation, and it only ever deletes.
create table customer_line_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  line_user_id text not null,
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, line_user_id),
  unique (business_id, customer_id)
);

create index customer_line_accounts_customer_idx on customer_line_accounts(business_id, customer_id);

create trigger customer_line_accounts_set_updated_at
  before update on customer_line_accounts
  for each row execute function set_updated_at();

alter table customer_line_accounts enable row level security;

create policy customer_line_accounts_select on customer_line_accounts
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: writes come only from the webhook
-- Edge Function (service_role) or unlink_customer_line_account (below).

-- customer_line_link_codes: short-lived, single-use, staff-generated
-- codes that let the webhook correlate an incoming LINE message to the
-- correct tenant/customer without ever trusting a client-supplied
-- line_user_id.
create table customer_line_link_codes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  code text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (code)
);

create index customer_line_link_codes_business_idx on customer_line_link_codes(business_id, customer_id);

alter table customer_line_link_codes enable row level security;

create policy customer_line_link_codes_select on customer_line_link_codes
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: created only by create_line_link_code
-- (below); consumed only by the webhook Edge Function (service_role).

-- follow_up_notifications: the reminder delivery ledger. UNIQUE on
-- follow_up_id is the DB-level "one reminder per follow-up" guarantee.
-- Written only by the two service_role-only claim functions and
-- complete_follow_up_notification below -- never by any client-facing
-- RPC or direct client write.
create table follow_up_notifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  follow_up_id uuid not null references follow_ups(id) on delete cascade,
  customer_line_account_id uuid references customer_line_accounts(id) on delete set null,
  status follow_up_notification_status not null default 'PENDING',
  attempt_count integer not null default 0,
  claimed_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (follow_up_id)
);

create index follow_up_notifications_status_idx on follow_up_notifications(business_id, status);

create trigger follow_up_notifications_set_updated_at
  before update on follow_up_notifications
  for each row execute function set_updated_at();

alter table follow_up_notifications enable row level security;

create policy follow_up_notifications_select on follow_up_notifications
  for select using (is_member(business_id));

-- No INSERT/UPDATE/DELETE policy: written only by the service_role-only
-- functions below (claim_due_follow_up_reminders,
-- claim_failed_follow_up_notifications, complete_follow_up_notification).

--------------------------------------------------------------------------
-- create_follow_up: client-facing creation RPC.
--------------------------------------------------------------------------
create or replace function create_follow_up(
  p_business_id uuid,
  p_customer_id uuid,
  p_assigned_staff_id uuid,
  p_due_date timestamptz,
  p_follow_up_notes text,
  p_consultation_id uuid,
  p_treatment_history_id uuid,
  p_appointment_id uuid
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_staff_valid boolean;
  v_staff_name text;
  v_record follow_ups;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to create a follow-up';
  end if;

  if p_due_date is null then
    raise exception 'Due date is required';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_assigned_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Assigned staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_assigned_staff_id;

  if p_consultation_id is not null and not exists (
    select 1 from consultations
    where id = p_consultation_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Consultation not found for this customer in this business';
  end if;

  if p_treatment_history_id is not null and not exists (
    select 1 from treatment_history
    where id = p_treatment_history_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Treatment record not found for this customer in this business';
  end if;

  if p_appointment_id is not null and not exists (
    select 1 from appointments
    where id = p_appointment_id and business_id = p_business_id and customer_id = p_customer_id
  ) then
    raise exception 'Appointment not found for this customer in this business';
  end if;

  insert into follow_ups (
    business_id, customer_id, assigned_staff_id, assigned_staff_name_snapshot,
    consultation_id, treatment_history_id, appointment_id,
    due_date, status, follow_up_notes, created_by
  ) values (
    p_business_id, p_customer_id, p_assigned_staff_id, coalesce(v_staff_name, ''),
    p_consultation_id, p_treatment_history_id, p_appointment_id,
    p_due_date, 'PENDING', p_follow_up_notes, auth.uid()
  ) returning * into v_record;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'follow_up', v_record.id, to_jsonb(v_record));

  return v_record;
end;
$$;

revoke execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) from public;
revoke execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) from anon;
grant execute on function create_follow_up(
  uuid, uuid, uuid, timestamptz, text, uuid, uuid, uuid
) to authenticated;

--------------------------------------------------------------------------
-- reschedule_follow_up: due_date + assigned_staff reassignment, PENDING
-- only. Re-derives the staff snapshot server-side if staff changes --
-- never trusts a client-supplied snapshot.
--------------------------------------------------------------------------
create or replace function reschedule_follow_up(
  p_business_id uuid,
  p_follow_up_id uuid,
  p_due_date timestamptz,
  p_assigned_staff_id uuid
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_follow_up follow_ups;
  v_staff_valid boolean;
  v_staff_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to reschedule a follow-up';
  end if;

  if p_due_date is null then
    raise exception 'Due date is required';
  end if;

  select * into v_follow_up from follow_ups
    where id = p_follow_up_id and business_id = p_business_id
    for update;

  if v_follow_up.id is null then
    raise exception 'Follow-up not found in this business';
  end if;

  if v_follow_up.status <> 'PENDING' then
    raise exception 'Only a pending follow-up can be rescheduled';
  end if;

  v_staff_valid := exists (
    select 1 from business_members
    where business_id = p_business_id and user_id = p_assigned_staff_id and active = true
  );
  if not v_staff_valid then
    raise exception 'Assigned staff member is not an active member of this business';
  end if;

  select full_name into v_staff_name from profiles where id = p_assigned_staff_id;

  perform set_config('app.trusted_follow_up_lifecycle_update', 'true', true);
  update follow_ups set
    due_date = p_due_date,
    assigned_staff_id = p_assigned_staff_id,
    assigned_staff_name_snapshot = coalesce(v_staff_name, '')
    where id = p_follow_up_id
    returning * into v_follow_up;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'follow_up', v_follow_up.id, to_jsonb(v_follow_up));

  return v_follow_up;
end;
$$;

revoke execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) from public;
revoke execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) from anon;
grant execute on function reschedule_follow_up(uuid, uuid, timestamptz, uuid) to authenticated;

--------------------------------------------------------------------------
-- set_follow_up_status: PENDING -> COMPLETED/MISSED/CANCELLED only.
-- completed_at/completed_by are server-set, never client-supplied.
--------------------------------------------------------------------------
create or replace function set_follow_up_status(
  p_business_id uuid,
  p_follow_up_id uuid,
  p_status follow_up_status
)
returns follow_ups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_follow_up follow_ups;
  v_allowed follow_up_status[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to update this follow-up';
  end if;

  select * into v_follow_up from follow_ups
    where id = p_follow_up_id and business_id = p_business_id
    for update;

  if v_follow_up.id is null then
    raise exception 'Follow-up not found in this business';
  end if;

  v_allowed := case v_follow_up.status
    when 'PENDING' then array['COMPLETED', 'MISSED', 'CANCELLED']::follow_up_status[]
    else array[]::follow_up_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move a follow-up from % to %', v_follow_up.status, p_status;
  end if;

  perform set_config('app.trusted_follow_up_lifecycle_update', 'true', true);
  update follow_ups set
    status = p_status,
    completed_at = case when p_status = 'COMPLETED' then now() else completed_at end,
    completed_by = case when p_status = 'COMPLETED' then auth.uid() else completed_by end
    where id = p_follow_up_id
    returning * into v_follow_up;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'follow_up', v_follow_up.id, to_jsonb(v_follow_up));

  return v_follow_up;
end;
$$;

revoke execute on function set_follow_up_status(uuid, uuid, follow_up_status) from public;
revoke execute on function set_follow_up_status(uuid, uuid, follow_up_status) from anon;
grant execute on function set_follow_up_status(uuid, uuid, follow_up_status) to authenticated;

--------------------------------------------------------------------------
-- create_line_link_code: staff-initiated, generates a short-lived 6-digit
-- code the customer sends to the LINE OA to complete linking. The actual
-- link is only ever written by the webhook, never by this function.
--------------------------------------------------------------------------
create or replace function create_line_link_code(
  p_business_id uuid,
  p_customer_id uuid
)
returns customer_line_link_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer customers;
  v_code text;
  v_record customer_line_link_codes;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to generate a LINE link code';
  end if;

  select * into v_customer from customers
    where id = p_customer_id and business_id = p_business_id;
  if v_customer.id is null then
    raise exception 'Customer not found in this business';
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  insert into customer_line_link_codes (business_id, customer_id, code, expires_at, created_by)
  values (p_business_id, p_customer_id, v_code, now() + interval '15 minutes', auth.uid())
  returning * into v_record;

  return v_record;
end;
$$;

revoke execute on function create_line_link_code(uuid, uuid) from public;
revoke execute on function create_line_link_code(uuid, uuid) from anon;
grant execute on function create_line_link_code(uuid, uuid) to authenticated;

--------------------------------------------------------------------------
-- unlink_customer_line_account: the only client-facing mutation of
-- customer_line_accounts, and it only ever deletes.
--------------------------------------------------------------------------
create or replace function unlink_customer_line_account(
  p_business_id uuid,
  p_customer_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to unlink a LINE account';
  end if;

  delete from customer_line_accounts
    where business_id = p_business_id and customer_id = p_customer_id;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (
    p_business_id, auth.uid(), 'DELETE', 'customer_line_account', p_customer_id,
    jsonb_build_object('customer_id', p_customer_id)
  );
end;
$$;

revoke execute on function unlink_customer_line_account(uuid, uuid) from public;
revoke execute on function unlink_customer_line_account(uuid, uuid) from anon;
grant execute on function unlink_customer_line_account(uuid, uuid) to authenticated;

--------------------------------------------------------------------------
-- claim_due_follow_up_reminders: service_role only (the reminder-worker
-- Edge Function). Atomically finds newly-eligible follow-ups (PENDING,
-- due within the reminder window, no existing notification row, has a
-- linked LINE account) and claims them by inserting the notification row
-- directly into SENDING -- the INSERT ... ON CONFLICT (follow_up_id) DO
-- NOTHING is the atomicity guarantee: under concurrent execution, only
-- one caller's insert can ever succeed for a given follow_up_id (backed
-- by the UNIQUE constraint), so this function can safely run from
-- overlapping cron invocations with no duplicate-claim window. Customers
-- with no linked LINE account are naturally excluded by the join, not
-- specially handled -- the follow-up itself remains untouched either way.
--------------------------------------------------------------------------
create or replace function claim_due_follow_up_reminders(p_reminder_window_minutes integer default 60)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with eligible as (
    select f.id as follow_up_id, f.business_id, f.customer_id, f.due_date,
           cla.id as customer_line_account_id, cla.line_user_id
    from follow_ups f
    join customer_line_accounts cla
      on cla.business_id = f.business_id and cla.customer_id = f.customer_id
    where f.status = 'PENDING'
      and f.due_date <= now() + (p_reminder_window_minutes || ' minutes')::interval
      and not exists (
        select 1 from follow_up_notifications n where n.follow_up_id = f.id
      )
  ),
  claimed as (
    insert into follow_up_notifications (business_id, follow_up_id, customer_line_account_id, status, claimed_at)
    select e.business_id, e.follow_up_id, e.customer_line_account_id, 'SENDING', now()
    from eligible e
    on conflict (follow_up_id) do nothing
    returning id, follow_up_id, business_id, customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, e.customer_id, c.customer_line_account_id,
         e.line_user_id, e.due_date, b.name
  from claimed c
  join eligible e on e.follow_up_id = c.follow_up_id
  join businesses b on b.id = c.business_id;
end;
$$;

revoke execute on function claim_due_follow_up_reminders(integer) from public;
revoke execute on function claim_due_follow_up_reminders(integer) from anon;
revoke execute on function claim_due_follow_up_reminders(integer) from authenticated;
grant execute on function claim_due_follow_up_reminders(integer) to service_role;

--------------------------------------------------------------------------
-- claim_failed_follow_up_notifications: service_role only. Re-claims
-- previously FAILED notifications for retry, atomically via a plain
-- UPDATE ... WHERE (Postgres row-level locking during the UPDATE is the
-- concurrency guarantee -- the same class of atomic-claim already proven
-- by record_sale_payment's own row locking elsewhere in this project).
-- A follow-up that was completed/missed/cancelled since the failure is
-- correctly excluded (the exists check re-reads current follow_ups.status
-- at claim time), so a stale FAILED row for an obsolete follow-up is
-- never retried.
--------------------------------------------------------------------------
create or replace function claim_failed_follow_up_notifications(p_max_attempts integer default 3)
returns table (
  notification_id uuid,
  follow_up_id uuid,
  business_id uuid,
  customer_id uuid,
  customer_line_account_id uuid,
  line_user_id text,
  due_date timestamptz,
  business_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update follow_up_notifications n set
      status = 'SENDING',
      claimed_at = now()
    where n.status = 'FAILED'
      and n.attempt_count < p_max_attempts
      and exists (
        select 1 from follow_ups f where f.id = n.follow_up_id and f.status = 'PENDING'
      )
    returning n.id, n.follow_up_id, n.business_id, n.customer_line_account_id
  )
  select c.id, c.follow_up_id, c.business_id, f.customer_id, c.customer_line_account_id,
         cla.line_user_id, f.due_date, b.name
  from claimed c
  join follow_ups f on f.id = c.follow_up_id
  join customer_line_accounts cla on cla.id = c.customer_line_account_id
  join businesses b on b.id = c.business_id;
end;
$$;

revoke execute on function claim_failed_follow_up_notifications(integer) from public;
revoke execute on function claim_failed_follow_up_notifications(integer) from anon;
revoke execute on function claim_failed_follow_up_notifications(integer) from authenticated;
grant execute on function claim_failed_follow_up_notifications(integer) to service_role;

--------------------------------------------------------------------------
-- complete_follow_up_notification: service_role only. Marks a claimed
-- (SENDING) notification SENT or FAILED after the actual LINE API call
-- completes. Notification outcome never touches follow_ups itself --
-- satisfies "notification failure must never change the follow-up
-- lifecycle."
--------------------------------------------------------------------------
create or replace function complete_follow_up_notification(
  p_notification_id uuid,
  p_success boolean,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update follow_up_notifications set
    status = case when p_success then 'SENT' else 'FAILED' end,
    sent_at = case when p_success then now() else sent_at end,
    attempt_count = attempt_count + 1,
    last_error = case when p_success then null else p_error end
    where id = p_notification_id and status = 'SENDING';
end;
$$;

revoke execute on function complete_follow_up_notification(uuid, boolean, text) from public;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from anon;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from authenticated;
grant execute on function complete_follow_up_notification(uuid, boolean, text) to service_role;
