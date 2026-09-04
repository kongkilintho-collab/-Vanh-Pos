// Live regression coverage for Phase 6 (Follow-up / Reminder + LINE OA) --
// supabase/migrations/0049_follow_ups_and_line_oa.sql: follow_ups,
// customer_line_accounts, customer_line_link_codes, follow_up_notifications,
// and the eight RPCs/functions defined there.
//
// Follows the same live QA project / fixture-account pattern as
// consultation_regression_test.dart / treatment_history_regression_test.dart,
// including both of that file's documented lessons (identity-protection
// mutates to a genuinely DIFFERENT value; cross-tenant SELECT is a
// documented fixture limitation, not asserted, because both QA fixture
// accounts are genuine dual-business members).
//
// The three service_role-only functions (claim_due_follow_up_reminders,
// claim_failed_follow_up_notifications, complete_follow_up_notification)
// are deliberately NOT exercised as "succeeding" calls here: this test
// environment only ever holds an anon/authenticated session (env.json
// never carries a service role key, by design -- see
// supabase/functions/reminder-worker/index.ts). What IS verified live is
// the negative case: an authenticated (non-service-role) caller is denied
// EXECUTE on all three, confirming the security boundary the LINE OA
// design depends on.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/follow_up_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/customers/data/follow_up_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/follow_up_status.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0049 applied and seeded with the QA fixture accounts.';
const _noStaffCashierFixture =
    'No STAFF- or CASHIER-rank fixture account exists (self-service .local '
    'signup is rejected by GoTrue in this project). CASHIER+ is exercised '
    'live on every successful call in this file, on the same '
    'has_role_at_least helper used throughout this codebase.';
const _dualBusinessFixtureLimitation =
    'Both QA fixture accounts (van@test.local, admin@test.local) are '
    'genuine dual-business members in this project (each is a real member '
    'of both Business A and Business B) -- no single-business-only account '
    'exists to validly test pure RLS SELECT denial. The write-side '
    'cross-tenant checks in this file do not depend on this and remain '
    'fully valid.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Matcher _deniedByRls() => isA<PostgrestException>().having((e) => e.code, 'code', '42501');

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('valid follow-up creation: server-derives staff snapshot, required fields enforced, '
      'audit log created, ordering, narrative (notes) update, identity protection with a '
      'genuinely different value, direct INSERT/DELETE denied', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final staffId = client.auth.currentUser!.id;

    // A second real staff/business-member id, for the identity-protection
    // re-check below -- a genuinely different value, not the same one.
    final secondStaffProfile =
        await client.from('profiles').select('id').neq('id', staffId).limit(1).maybeSingle();

    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'FollowUp Test Customer ${_uuid.v4()}'})
        .select()
        .single();
    // A second real customer in the SAME business, for the customer_id
    // identity-protection re-check below -- a genuinely different value,
    // not the same customer the follow-up already belongs to.
    final secondCustomer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'FollowUp Test Customer 2 ${_uuid.v4()}'})
        .select()
        .single();

    final repo = FollowUpRepository(client);

    // Required-field enforcement: server rejects a missing customer.
    await expectLater(
      client.rpc('create_follow_up', params: {
        'p_business_id': businessId,
        'p_customer_id': '00000000-0000-0000-0000-000000000000',
        'p_assigned_staff_id': staffId,
        'p_due_date': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
        'p_follow_up_notes': null,
        'p_consultation_id': null,
        'p_treatment_history_id': null,
        'p_appointment_id': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Required-field enforcement: server rejects a staff id that is not an
    // active member of this business.
    await expectLater(
      client.rpc('create_follow_up', params: {
        'p_business_id': businessId,
        'p_customer_id': customer['id'],
        'p_assigned_staff_id': '00000000-0000-0000-0000-000000000000',
        'p_due_date': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
        'p_follow_up_notes': null,
        'p_consultation_id': null,
        'p_treatment_history_id': null,
        'p_appointment_id': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('not an active member'))),
    );

    // Server-derived snapshot: creation sends no name.
    final followUp = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      assignedStaffId: staffId,
      dueDate: DateTime.now().add(const Duration(days: 7)),
      followUpNotes: 'Initial follow-up notes',
    );
    expect(followUp.assignedStaffId, staffId);
    expect(followUp.assignedStaffNameSnapshot, isNotEmpty);
    expect(followUp.status, FollowUpStatus.pending);
    expect(followUp.customerId, customer['id']);

    // Audit log created, exactly once.
    final auditRows = await client
        .from('audit_logs')
        .select('id, action, entity_type, entity_id')
        .eq('entity_type', 'follow_up')
        .eq('entity_id', followUp.id);
    expect((auditRows as List), hasLength(1));
    expect((auditRows.first as Map)['action'], 'CREATE');

    // Direct read via RLS.
    final direct = await client.from('follow_ups').select().eq('id', followUp.id).single();
    expect(direct['status'], 'PENDING');
    expect(direct['assigned_staff_name_snapshot'], followUp.assignedStaffNameSnapshot);

    // Direct INSERT denied (no policy exists at all).
    await expectLater(
      client.from('follow_ups').insert({
        'business_id': businessId,
        'customer_id': customer['id'],
        'assigned_staff_id': staffId,
        'assigned_staff_name_snapshot': 'x',
        'due_date': DateTime.now().toUtc().toIso8601String(),
      }),
      throwsA(_deniedByRls()),
    );

    // Direct DELETE denied (no policy exists at all).
    final deleted = await client.from('follow_ups').delete().eq('id', followUp.id).select();
    expect((deleted as List), isEmpty);
    final stillThere = await client.from('follow_ups').select('id').eq('id', followUp.id).single();
    expect(stillThere['id'], followUp.id);

    // Identity/lifecycle fields cannot be altered via direct UPDATE -- using
    // a GENUINELY DIFFERENT staff id, not the same one the row already has.
    if (secondStaffProfile != null) {
      await expectLater(
        client
            .from('follow_ups')
            .update({'assigned_staff_id': secondStaffProfile['id']})
            .eq('id', followUp.id)
            .select(),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify assigned staff, due date, status, or completion fields'),
        )),
      );
    }
    // due_date is also lifecycle-protected -- verify with a genuinely
    // different value too.
    await expectLater(
      client.from('follow_ups').update({'due_date': '2020-01-01T00:00:00Z'}).eq('id', followUp.id).select(),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot modify assigned staff, due date, status, or completion fields'),
      )),
    );
    // customer_id is a permanently-fixed identity field -- always rejected,
    // trusted flag or not. Uses a genuinely DIFFERENT, real customer id
    // (secondCustomer), not the follow-up's own existing customer_id --
    // writing back the same value is a harmless IS DISTINCT FROM no-op,
    // not a valid rejection test.
    await expectLater(
      client.from('follow_ups').update({'customer_id': secondCustomer['id']}).eq('id', followUp.id).select(),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot modify identity fields'),
      )),
    );

    // Narrative field (follow_up_notes) CAN be updated directly (authorized,
    // CASHIER+ owner).
    await repo.updateNotes(id: followUp.id, followUpNotes: 'Updated notes');
    final afterUpdate =
        await client.from('follow_ups').select('follow_up_notes').eq('id', followUp.id).single();
    expect(afterUpdate['follow_up_notes'], 'Updated notes');

    // Ordering: a second, later-due follow-up for the same customer must
    // come first in listForCustomer's descending order.
    final later = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      assignedStaffId: staffId,
      dueDate: DateTime.now().add(const Duration(days: 30)),
    );
    final history = await repo.listForCustomer(businessId, customer['id'] as String);
    expect(history.first.id, later.id);
  });

  test('reschedule_follow_up: updates due date + staff (re-deriving the snapshot), only '
      'permitted while PENDING', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final staffId = client.auth.currentUser!.id;
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'FollowUp Reschedule Customer ${_uuid.v4()}'})
        .select()
        .single();

    final repo = FollowUpRepository(client);
    final followUp = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      assignedStaffId: staffId,
      dueDate: DateTime.now().add(const Duration(days: 3)),
    );

    final newDue = DateTime.now().add(const Duration(days: 10));
    final rescheduled = await repo.reschedule(
      businessId: businessId,
      followUpId: followUp.id,
      dueDate: newDue,
      assignedStaffId: staffId,
    );
    expect(rescheduled.dueDate.toUtc().difference(newDue.toUtc()).inSeconds.abs() < 2, isTrue);
    expect(rescheduled.status, FollowUpStatus.pending);

    // Move to a terminal state, then verify reschedule is rejected.
    await repo.setStatus(businessId: businessId, followUpId: followUp.id, status: FollowUpStatus.cancelled);
    await expectLater(
      repo.reschedule(
        businessId: businessId,
        followUpId: followUp.id,
        dueDate: DateTime.now().add(const Duration(days: 20)),
        assignedStaffId: staffId,
      ),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Only a pending follow-up can be rescheduled'),
      )),
    );
  });

  test('set_follow_up_status: state machine (PENDING -> COMPLETED/MISSED/CANCELLED only, all '
      'terminal), completed_at/completed_by are server-set and not client-forgeable', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final staffId = client.auth.currentUser!.id;
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'FollowUp Status Customer ${_uuid.v4()}'})
        .select()
        .single();

    final repo = FollowUpRepository(client);
    final followUp = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      assignedStaffId: staffId,
      dueDate: DateTime.now().add(const Duration(days: 1)),
    );

    // Invalid target from PENDING is rejected (PENDING itself is not a
    // valid transition target).
    await expectLater(
      repo.setStatus(businessId: businessId, followUpId: followUp.id, status: FollowUpStatus.pending),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot move a follow-up from'),
      )),
    );

    final completed =
        await repo.setStatus(businessId: businessId, followUpId: followUp.id, status: FollowUpStatus.completed);
    expect(completed.status, FollowUpStatus.completed);
    expect(completed.completedAt, isNotNull);
    expect(completed.completedBy, staffId);

    // Terminal: a second transition from COMPLETED is rejected.
    await expectLater(
      repo.setStatus(businessId: businessId, followUpId: followUp.id, status: FollowUpStatus.missed),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot move a follow-up from'),
      )),
    );

    // completed_at/completed_by cannot be forged via direct UPDATE either --
    // covered generically by the identity-protection test above, but
    // reconfirmed here on the now-COMPLETED row for these two fields
    // specifically.
    await expectLater(
      client
          .from('follow_ups')
          .update({'completed_by': staffId, 'completed_at': '2020-01-01T00:00:00Z'})
          .eq('id', followUp.id)
          .select(),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot modify assigned staff, due date, status, or completion fields'),
      )),
    );
  });

  test('anon EXECUTE on create_follow_up is denied', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await client.auth.signOut();
    await expectLater(
      client.rpc('create_follow_up', params: {
        'p_business_id': '00000000-0000-0000-0000-000000000000',
        'p_customer_id': '00000000-0000-0000-0000-000000000000',
        'p_assigned_staff_id': '00000000-0000-0000-0000-000000000000',
        'p_due_date': DateTime.now().toUtc().toIso8601String(),
        'p_follow_up_notes': null,
        'p_consultation_id': null,
        'p_treatment_history_id': null,
        'p_appointment_id': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
  });

  test('security boundary: an authenticated (non-service-role) caller is denied EXECUTE on all '
      'three service_role-only reminder-worker functions', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);

    await expectLater(
      client.rpc('claim_due_follow_up_reminders', params: {'p_reminder_window_minutes': 60}),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
    await expectLater(
      client.rpc('claim_failed_follow_up_notifications', params: {'p_max_attempts': 3}),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
    await expectLater(
      client.rpc('complete_follow_up_notification', params: {
        'p_notification_id': '00000000-0000-0000-0000-000000000000',
        'p_success': true,
        'p_error': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
  });

  test('role authorization: CASHIER+ successfully creates a follow-up '
      '(no STAFF/CASHIER-below fixture exists to test denial live)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    markTestSkipped(_noStaffCashierFixture);
  });

  test('tenant isolation: customer/staff from another business are rejected on create_follow_up; '
      'cross-tenant SELECT has a documented fixture limitation', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;

    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessIdA = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final staffIdA = client.auth.currentUser!.id;
    final customerA = await client
        .from('customers')
        .insert({'business_id': businessIdA, 'name': 'Tenant FollowUp Customer A ${_uuid.v4()}'})
        .select()
        .single();

    final recordA = await FollowUpRepository(client).create(
      businessId: businessIdA,
      customerId: customerA['id'] as String,
      assignedStaffId: staffIdA,
      dueDate: DateTime.now().add(const Duration(days: 5)),
    );

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner && m.business.id != businessIdA)
        .business
        .id;
    final staffIdB = client.auth.currentUser!.id;

    // Cross-tenant customer: Business B scoped to its own business_id, but
    // targeting Business A's real customer -- rejected.
    await expectLater(
      client.rpc('create_follow_up', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerA['id'],
        'p_assigned_staff_id': staffIdB,
        'p_due_date': DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
        'p_follow_up_notes': null,
        'p_consultation_id': null,
        'p_treatment_history_id': null,
        'p_appointment_id': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Non-member staff: Business B's own customer, but a fabricated,
    // non-existent staff id -- NOT staffIdA, because van@test.local is a
    // genuine active member of BOTH businesses in this QA project (see
    // _dualBusinessFixtureLimitation), so using it as the "foreign" staff
    // would be a false-positive rejection test (create_follow_up would
    // correctly succeed, not reject). A fabricated UUID exercises the
    // exact same `exists (select 1 from business_members where ...)`
    // code path with no ambiguity, matching the invalid-staff case
    // already used earlier in this same test file (line ~127).
    final customerB = await client
        .from('customers')
        .insert({'business_id': businessIdB, 'name': 'Tenant FollowUp Customer B ${_uuid.v4()}'})
        .select()
        .single();
    await expectLater(
      client.rpc('create_follow_up', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerB['id'],
        'p_assigned_staff_id': '00000000-0000-0000-0000-000000000000',
        'p_due_date': DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
        'p_follow_up_notes': null,
        'p_consultation_id': null,
        'p_treatment_history_id': null,
        'p_appointment_id': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('not an active member'))),
    );

    // Cross-tenant SELECT is deliberately NOT asserted here: both QA
    // fixture accounts are genuine dual-business members (see
    // _dualBusinessFixtureLimitation), so a SELECT of recordA.id from this
    // admin@test.local session would legitimately succeed (real ADMIN
    // membership in Business A), not indicate a leak. Documented via the
    // dedicated skip-only test below rather than asserted incorrectly here.
    expect(recordA.id, isNotEmpty);
  });

  test('cross-tenant SELECT: known fixture limitation (documented, not asserted)', () async {
    markTestSkipped(_dualBusinessFixtureLimitation);
  });

  test('LINE linking: create_line_link_code succeeds for a real tenant-scoped customer and is '
      'rejected for a cross-tenant customer; direct writes to customer_line_accounts/'
      'customer_line_link_codes are denied by RLS; unlink_customer_line_account is safe to call '
      'with no existing link and logs an audit entry', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessIdA = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final customerA = await client
        .from('customers')
        .insert({'business_id': businessIdA, 'name': 'LINE Link Customer A ${_uuid.v4()}'})
        .select()
        .single();

    final repo = FollowUpRepository(client);
    final code = await repo.createLineLinkCode(businessIdA, customerA['id'] as String);
    expect(code, hasLength(6));
    expect(int.tryParse(code), isNotNull);

    // Direct read via RLS confirms the code row exists, unconsumed.
    final direct = await client
        .from('customer_line_link_codes')
        .select('code, consumed_at, expires_at')
        .eq('code', code)
        .single();
    expect(direct['consumed_at'], isNull);
    expect(DateTime.parse(direct['expires_at'] as String).isAfter(DateTime.now().toUtc()), isTrue);

    // Direct INSERT into customer_line_link_codes denied (no policy exists
    // at all -- only create_line_link_code and the webhook, via
    // service_role, may write here).
    await expectLater(
      client.from('customer_line_link_codes').insert({
        'business_id': businessIdA,
        'customer_id': customerA['id'],
        'code': _uuid.v4().substring(0, 6),
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String(),
      }),
      throwsA(_deniedByRls()),
    );

    // Direct INSERT into customer_line_accounts denied (no policy exists at
    // all -- only the webhook, via service_role, may write here).
    await expectLater(
      client.from('customer_line_accounts').insert({
        'business_id': businessIdA,
        'customer_id': customerA['id'],
        'line_user_id': 'U${_uuid.v4()}',
      }),
      throwsA(_deniedByRls()),
    );

    // Cross-tenant customer for create_line_link_code is rejected.
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner && m.business.id != businessIdA)
        .business
        .id;
    await expectLater(
      client.rpc('create_line_link_code', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerA['id'],
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // unlink_customer_line_account is safe to call even when no link
    // exists (deletes zero rows) and still logs an audit entry -- this
    // business's own customer, own business_id.
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    await repo.unlinkLineAccount(businessIdA, customerA['id'] as String);
    final unlinkAuditRows = await client
        .from('audit_logs')
        .select('id, action, entity_type')
        .eq('entity_type', 'customer_line_account')
        .eq('entity_id', customerA['id'])
        .eq('action', 'DELETE');
    expect((unlinkAuditRows as List), isNotEmpty);

    // getLineLinkedAt correctly reports "not linked" (never fetches
    // line_user_id -- see FollowUpRepository.getLineLinkedAt).
    final linkedAt = await repo.getLineLinkedAt(businessIdA, customerA['id'] as String);
    expect(linkedAt, isNull);
  });
}
