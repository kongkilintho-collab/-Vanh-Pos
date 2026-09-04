// Phase 6: follow-up reminder worker.
//
// Responsibilities (and ONLY these):
//   1. Atomically claim due follow-up reminders, previously-failed
//      notifications still eligible for retry, and stale (crashed-mid-send)
//      SENDING notifications, via the two service_role-only RPCs defined in
//      supabase/migrations/0049_follow_ups_and_line_oa.sql and refined by
//      0050_follow_up_notification_stale_reclaim.sql
//      (claim_due_follow_up_reminders / claim_failed_follow_up_notifications).
//      The claim itself -- not this function -- is what guarantees at most
//      one row ever exists per follow-up and at most one caller ever holds
//      an active claim on it at a time (see 0050's comments for the full
//      reasoning, including the honest limitation: this is database-level
//      duplicate prevention, NOT an exactly-once external LINE delivery
//      guarantee -- a worker that crashes after LINE accepts the message
//      but before recording SENT can cause a stale reclaim to resend).
//      This function only ever acts on rows the database has already
//      atomically handed to it.
//   2. Send one deterministic, non-marketing LINE Push Message per
//      claimed notification.
//   3. Record the outcome via complete_follow_up_notification --
//      success or failure -- which updates ONLY the notification ledger.
//      A delivery failure NEVER touches follow_ups itself; the follow-up
//      lifecycle is completely independent of notification delivery.
//
// Required secrets (see deployment notes at the bottom of this file):
//   LINE_CHANNEL_ACCESS_TOKEN -- used only for the Push Message API call.
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY -- auto-injected by Supabase.
//   REMINDER_WORKER_SHARED_SECRET -- a secret this function requires the
//     caller to present (as `Authorization: Bearer <secret>`), so that
//     only the scheduled pg_cron/pg_net job (or another trusted, secret-
//     holding caller) can trigger a send -- defense in depth on top of
//     Supabase's own platform-level JWT verification on the function URL.
import { createClient } from 'npm:@supabase/supabase-js@2';

const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const REMINDER_WORKER_SHARED_SECRET = Deno.env.get('REMINDER_WORKER_SHARED_SECRET') ?? '';

interface ClaimedReminder {
  notification_id: string;
  follow_up_id: string;
  business_id: string;
  customer_id: string;
  customer_line_account_id: string;
  line_user_id: string;
  due_date: string;
  business_name: string;
}

function formatDueDate(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// Deterministic, template-only message -- no marketing content, no AI
// generation, no broadcast content, matching the approved scope.
function buildMessage(reminder: ClaimedReminder): string {
  return `Hi! This is a reminder from ${reminder.business_name} about your upcoming follow-up appointment scheduled for ${formatDueDate(reminder.due_date)}. Please contact us if you have any questions.`;
}

async function sendLinePush(lineUserId: string, text: string): Promise<{ ok: boolean; error?: string }> {
  if (!LINE_CHANNEL_ACCESS_TOKEN) {
    return { ok: false, error: 'LINE_CHANNEL_ACCESS_TOKEN is not configured' };
  }
  try {
    const res = await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({ to: lineUserId, messages: [{ type: 'text', text }] }),
    });
    if (!res.ok) {
      const body = await res.text();
      return { ok: false, error: `LINE API ${res.status}: ${body.slice(0, 500)}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err).slice(0, 500) };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  // Fail-closed: an unconfigured secret must reject every request, never
  // skip the check (mirrors line-webhook's own
  // `if (!signature || !LINE_CHANNEL_SECRET) return false` fail-closed
  // behavior for an unconfigured LINE_CHANNEL_SECRET).
  if (!REMINDER_WORKER_SHARED_SECRET) {
    return new Response('Unauthorized', { status: 401 });
  }
  const auth = req.headers.get('authorization') ?? '';
  if (auth !== `Bearer ${REMINDER_WORKER_SHARED_SECRET}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return new Response('Server misconfigured', { status: 500 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const [dueResult, failedResult] = await Promise.all([
    supabase.rpc('claim_due_follow_up_reminders', { p_reminder_window_minutes: 60 }),
    supabase.rpc('claim_failed_follow_up_notifications', { p_max_attempts: 3 }),
  ]);

  if (dueResult.error || failedResult.error) {
    return new Response(
      JSON.stringify({ error: dueResult.error?.message ?? failedResult.error?.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const claimed: ClaimedReminder[] = [...(dueResult.data ?? []), ...(failedResult.data ?? [])];

  let sent = 0;
  let failed = 0;

  for (const reminder of claimed) {
    const result = await sendLinePush(reminder.line_user_id, buildMessage(reminder));
    if (result.ok) {
      sent += 1;
    } else {
      failed += 1;
    }
    await supabase.rpc('complete_follow_up_notification', {
      p_notification_id: reminder.notification_id,
      p_success: result.ok,
      p_error: result.ok ? null : result.error,
    });
  }

  return new Response(
    JSON.stringify({ claimed: claimed.length, sent, failed }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});

// --- Deployment notes (manual steps -- NOT performed by this change) ---
// 1. `supabase functions deploy reminder-worker`
// 2. `supabase secrets set LINE_CHANNEL_ACCESS_TOKEN=... REMINDER_WORKER_SHARED_SECRET=...`
// 3. Enable the pg_cron and pg_net extensions for this project (Supabase
//    Dashboard -> Database -> Extensions), then schedule, e.g. every 15
//    minutes:
//
//    select cron.schedule(
//      'follow-up-reminder-worker',
//      '*/15 * * * *',
//      $$
//      select net.http_post(
//        url := 'https://<project-ref>.functions.supabase.co/reminder-worker',
//        headers := jsonb_build_object(
//          'Content-Type', 'application/json',
//          'Authorization', 'Bearer <REMINDER_WORKER_SHARED_SECRET>'
//        ),
//        body := '{}'::jsonb
//      );
//      $$
//    );
//
//    This is intentionally NOT included as a migration: it requires the
//    real secret value inline, which must never be committed to git.
//    Run it manually (with the real secret substituted) via the Supabase
//    SQL Editor after both extensions are enabled and secrets are set.
