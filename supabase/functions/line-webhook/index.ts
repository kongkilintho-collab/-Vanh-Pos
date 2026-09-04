// Phase 6: LINE Official Account webhook.
//
// Responsibilities (and ONLY these):
//   1. Verify every inbound request's `x-line-signature` header
//      (HMAC-SHA256 over the raw request body, keyed with the LINE
//      Channel Secret) before touching the payload at all. Any request
//      that fails verification is rejected outright with 401 -- no
//      event from an unverified request is ever processed.
//   2. For each inbound text-message event, treat the message text as a
//      candidate linking code (see create_line_link_code in
//      supabase/migrations/0049_follow_ups_and_line_oa.sql), atomically
//      consume a matching, unexpired, unconsumed
//      customer_line_link_codes row, and -- ONLY if that succeeds --
//      write the resulting (business_id, customer_id, line_user_id) into
//      customer_line_accounts.
//
// This function is the ONLY place in the whole system that is permitted
// to resolve line_user_id from a source LINE itself vouches for (the
// signed webhook payload's event.source.userId) and write it into
// customer_line_accounts. Flutter/the client never supplies, sees, or
// claims a line_user_id anywhere -- satisfying the non-negotiable
// requirement that the customer<->LINE identity link can only ever be
// established server-side, from a source LINE itself authenticates.
//
// Required secrets (set via `supabase secrets set`, NEVER committed to
// git, NEVER placed in env.json/Dart source -- see the deployment notes
// at the bottom of this file):
//   LINE_CHANNEL_SECRET       -- used only for signature verification.
//   LINE_CHANNEL_ACCESS_TOKEN -- used only for the reply message.
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY -- Supabase auto-injects
//     these into every Edge Function's environment; do not set manually.
//
// This function talks to Postgres using the service_role key, which
// bypasses RLS entirely -- appropriate here because customer_line_accounts
// and customer_line_link_codes both deliberately have NO client-facing
// INSERT/UPDATE policy (see 0049); this webhook is one of the only two
// legitimate writers, the other being unlink_customer_line_account (an
// authenticated RPC that only ever deletes).
import { createClient } from 'npm:@supabase/supabase-js@2';

const LINE_CHANNEL_SECRET = Deno.env.get('LINE_CHANNEL_SECRET') ?? '';
const LINE_CHANNEL_ACCESS_TOKEN = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

interface LineEventSource {
  type: string;
  userId?: string;
}

interface LineEventMessage {
  type: string;
  text?: string;
}

interface LineEvent {
  type: string;
  replyToken?: string;
  source?: LineEventSource;
  message?: LineEventMessage;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

async function verifySignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature || !LINE_CHANNEL_SECRET) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(LINE_CHANNEL_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return timingSafeEqual(expected, signature);
}

async function replyMessage(replyToken: string | undefined, text: string): Promise<void> {
  if (!replyToken || !LINE_CHANNEL_ACCESS_TOKEN) return;
  try {
    await fetch('https://api.line.me/v2/bot/message/reply', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({ replyToken, messages: [{ type: 'text', text }] }),
    });
  } catch {
    // Reply failures are best-effort UX only -- never let a reply error
    // affect the linking outcome that already happened.
  }
}

// deno-lint-ignore no-explicit-any
async function handleEvent(supabase: any, event: LineEvent): Promise<void> {
  if (event.type !== 'message' || event.message?.type !== 'text') return;
  if (event.source?.type !== 'user' || !event.source.userId) return;

  const lineUserId = event.source.userId;
  const code = (event.message.text ?? '').trim();
  if (!code) return;

  const { data: linkCode } = await supabase
    .from('customer_line_link_codes')
    .select('id, business_id, customer_id, expires_at, consumed_at')
    .eq('code', code)
    .is('consumed_at', null)
    .maybeSingle();

  if (!linkCode || new Date(linkCode.expires_at).getTime() <= Date.now()) {
    await replyMessage(event.replyToken, 'This code is invalid or has expired. Please ask staff for a new linking code.');
    return;
  }

  // Atomic claim: only the first request to successfully flip
  // consumed_at from null wins. A concurrent duplicate message with the
  // same code (or a resend) can never consume the same code twice.
  const { data: consumed } = await supabase
    .from('customer_line_link_codes')
    .update({ consumed_at: new Date().toISOString() })
    .eq('id', linkCode.id)
    .is('consumed_at', null)
    .select('id')
    .maybeSingle();

  if (!consumed) {
    await replyMessage(event.replyToken, 'This code has already been used. Please ask staff for a new linking code.');
    return;
  }

  const { error: insertError } = await supabase.from('customer_line_accounts').insert({
    business_id: linkCode.business_id,
    customer_id: linkCode.customer_id,
    line_user_id: lineUserId,
  });

  if (insertError) {
    // unique(business_id, line_user_id) or unique(business_id, customer_id)
    // already satisfied by a prior link -- never silently reassign an
    // existing link; require staff/customer to explicitly unlink first.
    await replyMessage(
      event.replyToken,
      'This LINE account or customer already has a link on file. Please contact the business if you need to update it.',
    );
    return;
  }

  await replyMessage(event.replyToken, 'Your LINE account has been linked successfully. You will receive follow-up reminders here.');
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const rawBody = await req.text();
  const signature = req.headers.get('x-line-signature');

  if (!(await verifySignature(rawBody, signature))) {
    return new Response('Invalid signature', { status: 401 });
  }

  let payload: { events?: LineEvent[] };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const events = payload.events ?? [];
  if (events.length === 0 || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return new Response('OK', { status: 200 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  for (const event of events) {
    await handleEvent(supabase, event);
  }

  return new Response('OK', { status: 200 });
});

// --- Deployment notes (manual steps -- NOT performed by this change) ---
// 1. `supabase functions deploy line-webhook`
// 2. `supabase secrets set LINE_CHANNEL_SECRET=... LINE_CHANNEL_ACCESS_TOKEN=...`
// 3. In the LINE Developers console, set the webhook URL to this
//    function's deployed URL and enable "Use webhook".
