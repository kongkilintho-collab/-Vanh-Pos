-- Phase 6 remediation (forensic finding MEDIUM-2): a notification claimed
-- into SENDING had no recovery path if the worker crashed/was killed
-- between claim and completion (claim_failed_follow_up_notifications only
-- ever matched status = 'FAILED'), permanently stranding it. This
-- migration adds a bounded stale-claim reclaim, in place, without
-- changing any function's signature, table shape, RLS, or grants.
--
-- Design:
--   - attempt_count now increments at CLAIM time (both the very first
--     claim and every reclaim), not at completion time -- an attempt
--     that never reaches complete_follow_up_notification (a crash) must
--     still count against p_max_attempts, or a persistently-crashing
--     notification could be reclaimed forever. complete_follow_up_notification
--     therefore no longer increments attempt_count itself (moving the
--     increment there again would double-count every attempt that DOES
--     complete normally).
--   - claim_failed_follow_up_notifications' WHERE clause gains a second
--     OR-branch: a SENDING row is reclaimable once its claimed_at is
--     older than a fixed 5-minute staleness threshold. 5 minutes is
--     conservative for this worker's actual shape (one sequential LINE
--     Push API call per claimed row, each normally resolving in low
--     single-digit seconds) while still recovering well within a single
--     pg_cron run cycle (documented as ~15 minutes in
--     supabase/functions/reminder-worker/index.ts's own deployment
--     notes) rather than waiting for the next one.
--   - Both branches remain gated by the SAME atomic UPDATE ... WHERE
--     statement as before -- this is still one plain UPDATE, so Postgres
--     row-level locking is the entire concurrency guarantee: a second
--     concurrent caller's UPDATE on the same row blocks until the first
--     commits, then re-evaluates the WHERE clause against the now-fresh
--     claimed_at/attempt_count the first caller just wrote, and no longer
--     matches. Two workers can never simultaneously believe they own the
--     same notification, and no second notification row is ever created
--     (the unique(follow_up_id) constraint and both claim functions'
--     row-scoped logic are otherwise completely unchanged).
--
-- Explicit, non-hidden limitation (crash-window duplicate-send risk):
--   Worker A claims a notification -> calls the LINE Push API -> LINE
--   accepts and actually delivers the message -> Worker A crashes before
--   it can call complete_follow_up_notification -> the row is still
--   SENDING -> after the staleness threshold elapses, Worker B reclaims
--   the SAME notification and sends AGAIN. This is a real, inherent
--   at-least-once-delivery trade-off, not something this migration (or
--   any purely database-level mechanism) can eliminate -- LINE's own API
--   gives no way to ask "did my last request actually succeed?" after a
--   crash wiped the in-memory result. What this migration guarantees is
--   strictly narrower and is the correct guarantee to claim:
--     - at most one row ever exists per follow_up_id (unchanged)
--     - at most one caller ever holds an active claim on that row at a
--       time (unchanged, still atomic)
--     - a stuck claim is bounded (recovered after ~5 minutes, and overall
--       reclaim attempts remain bounded by p_max_attempts, same as any
--       ordinary FAILED retry)
--   It does NOT and cannot guarantee exactly-once external LINE delivery.
--
-- Residual edge case (documented, not engineered around, per the
-- instruction not to add speculative complexity beyond what was asked):
-- if a notification crashes mid-send on p_max_attempts consecutive
-- reclaims in a row, it stops being reclaimed (attempt_count reaches
-- p_max_attempts) while still sitting in SENDING rather than FAILED.
-- This requires the same single notification to hit the exact crash
-- window multiple times consecutively -- an extremely low-probability
-- compound event -- and is recoverable manually via the notification
-- ledger if it is ever observed. Not addressed here to avoid adding a
-- second bookkeeping mechanism beyond the existing attempt_count/status
-- model for a scenario this unlikely.

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
    insert into follow_up_notifications (
      business_id, follow_up_id, customer_line_account_id, status, claimed_at, attempt_count
    )
    select e.business_id, e.follow_up_id, e.customer_line_account_id, 'SENDING', now(), 1
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
      claimed_at = now(),
      attempt_count = attempt_count + 1
    where n.attempt_count < p_max_attempts
      and (
        n.status = 'FAILED'
        or (n.status = 'SENDING' and n.claimed_at < now() - interval '5 minutes')
      )
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
    last_error = case when p_success then null else p_error end
    where id = p_notification_id and status = 'SENDING';
end;
$$;

-- create or replace function preserves the existing grants (same name,
-- same argument signature for all three functions -- no new overload is
-- created), so no revoke/grant statements are required here. Re-asserted
-- anyway, defensively and idempotently, to leave zero ambiguity that the
-- service_role-only boundary is unchanged by this migration.
revoke execute on function claim_due_follow_up_reminders(integer) from public;
revoke execute on function claim_due_follow_up_reminders(integer) from anon;
revoke execute on function claim_due_follow_up_reminders(integer) from authenticated;
grant execute on function claim_due_follow_up_reminders(integer) to service_role;

revoke execute on function claim_failed_follow_up_notifications(integer) from public;
revoke execute on function claim_failed_follow_up_notifications(integer) from anon;
revoke execute on function claim_failed_follow_up_notifications(integer) from authenticated;
grant execute on function claim_failed_follow_up_notifications(integer) to service_role;

revoke execute on function complete_follow_up_notification(uuid, boolean, text) from public;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from anon;
revoke execute on function complete_follow_up_notification(uuid, boolean, text) from authenticated;
grant execute on function complete_follow_up_notification(uuid, boolean, text) to service_role;
