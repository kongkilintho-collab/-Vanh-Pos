// Live regression coverage for Phase 4 (Customer Treatment History) --
// supabase/migrations/0047_treatment_history.sql: the treatment_history
// table, create_treatment_record (manual/walk-in entry), and the
// set_appointment_status extension (auto-creation at appointment
// completion).
//
// Follows the same live QA project / fixture-account pattern as the other
// integration tests in this directory.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/treatment_history_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/appointments/data/appointment_repository.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/customers/data/treatment_history_repository.dart';
import 'package:beauty_clinic_pos/shared/models/appointment_item.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:decimal/decimal.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0047 applied and seeded with the QA fixture accounts.';
const _noStaffCashierFixture =
    'No STAFF- or CASHIER-rank fixture account exists (self-service .local '
    'signup is rejected by GoTrue in this project). CASHIER+ is exercised '
    'live on every successful call in this file, on the same '
    'has_role_at_least helper used throughout this codebase.';

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

  test('manual treatment creation: server-derives snapshots, required fields enforced, '
      'audit log created, RLS read/delete/identity-protection all hold', () async {
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

    final realServiceName = 'Treatment Test Service ${_uuid.v4()}';
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': realServiceName, 'price': 100000})
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'Treatment Test Customer ${_uuid.v4()}'})
        .select()
        .single();

    final repo = TreatmentHistoryRepository(client);

    // Required-field enforcement: server rejects a missing customer/service/staff.
    await expectLater(
      client.rpc('create_treatment_record', params: {
        'p_business_id': businessId,
        'p_customer_id': '00000000-0000-0000-0000-000000000000',
        'p_service_id': service['id'],
        'p_staff_id': staffId,
        'p_treatment_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_appointment_item_id': null,
        'p_sale_id': null,
        'p_notes': null,
        'p_result': null,
        'p_customer_feedback': null,
        'p_before_after_reference': null,
        'p_follow_up_date': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Server-derived snapshots: creation call sends no name at all.
    final record = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      serviceId: service['id'] as String,
      staffId: staffId,
      treatmentDate: DateTime.now(),
      notes: 'Initial notes',
      result: 'Good result',
      customerFeedback: 'Happy',
      beforeAfterReference: 'https://example.com/photo.jpg',
      followUpDate: DateTime.now().add(const Duration(days: 14)),
    );
    expect(record.serviceNameSnapshot, realServiceName);
    expect(record.customerId, customer['id']);
    expect(record.staffId, staffId);
    expect(record.appointmentId, isNull);
    expect(record.appointmentItemId, isNull);

    // Audit log created.
    final auditRows = await client
        .from('audit_logs')
        .select('id, action, entity_type, entity_id')
        .eq('entity_type', 'treatment_history')
        .eq('entity_id', record.id);
    expect((auditRows as List), hasLength(1));
    expect((auditRows.first as Map)['action'], 'CREATE');

    // Direct read via RLS.
    final direct = await client.from('treatment_history').select().eq('id', record.id).single();
    expect(direct['service_name_snapshot'], realServiceName);

    // Direct DELETE denied (no policy exists at all).
    final deleted = await client.from('treatment_history').delete().eq('id', record.id).select();
    expect((deleted as List), isEmpty);
    final stillThere = await client.from('treatment_history').select('id').eq('id', record.id).single();
    expect(stillThere['id'], record.id);

    // Identity fields cannot be altered via direct UPDATE.
    await expectLater(
      client.from('treatment_history').update({'service_id': service['id']}).eq('id', record.id).select(),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot modify identity or snapshot fields'),
      )),
    );

    // Narrative fields CAN be updated (authorized, CASHIER+ owner).
    await repo.updateNarrative(id: record.id, notes: 'Updated notes', result: 'Improved');
    final afterUpdate = await client.from('treatment_history').select('notes, result').eq('id', record.id).single();
    expect(afterUpdate['notes'], 'Updated notes');
    expect(afterUpdate['result'], 'Improved');
  });

  test('a direct INSERT into treatment_history is denied by RLS', () async {
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

    await expectLater(
      client.from('treatment_history').insert({
        'business_id': businessId,
        'customer_id': '00000000-0000-0000-0000-000000000000',
        'service_id': '00000000-0000-0000-0000-000000000000',
        'staff_id': '00000000-0000-0000-0000-000000000000',
        'service_name_snapshot': 'x',
        'staff_name_snapshot': 'x',
        'treatment_date': DateTime.now().toUtc().toIso8601String(),
      }),
      throwsA(_deniedByRls()),
    );
  });

  test('tenant isolation: Business B cannot create a treatment for Business A\'s customer, '
      'and cannot read Business A\'s treatment records', () async {
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
    final serviceA = await client
        .from('services')
        .insert({'business_id': businessIdA, 'name': 'Tenant Test Service A ${_uuid.v4()}', 'price': 50000})
        .select()
        .single();
    final customerA = await client
        .from('customers')
        .insert({'business_id': businessIdA, 'name': 'Tenant Test Customer A ${_uuid.v4()}'})
        .select()
        .single();
    final recordA = await TreatmentHistoryRepository(client).create(
      businessId: businessIdA,
      customerId: customerA['id'] as String,
      serviceId: serviceA['id'] as String,
      staffId: staffIdA,
      treatmentDate: DateTime.now(),
    );

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner && m.business.id != businessIdA)
        .business
        .id;

    // Cross-tenant write: Business B scoped to its own business_id, but
    // targeting Business A's real customer -- rejected.
    await expectLater(
      client.rpc('create_treatment_record', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerA['id'],
        'p_service_id': serviceA['id'],
        'p_staff_id': staffIdA,
        'p_treatment_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_appointment_item_id': null,
        'p_sale_id': null,
        'p_notes': null,
        'p_result': null,
        'p_customer_feedback': null,
        'p_before_after_reference': null,
        'p_follow_up_date': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Cross-tenant read: Business B cannot see Business A's treatment row.
    final crossRead = await client.from('treatment_history').select('id').eq('id', recordA.id);
    expect((crossRead as List), isEmpty);
  });

  test('role authorization: CASHIER+ successfully creates a treatment record '
      '(no STAFF/CASHIER-below fixture exists to test denial live)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    markTestSkipped(_noStaffCashierFixture);
  });

  test('appointment completion: creates one treatment per item, correct customer/service/staff, '
      'nullable-customer appointment skipped, repeated completion attempt does not duplicate', () async {
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

    final serviceA = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Appt Treatment Service A ${_uuid.v4()}', 'price': 80000})
        .select()
        .single();
    final serviceB = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Appt Treatment Service B ${_uuid.v4()}', 'price': 120000})
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'Appt Treatment Customer ${_uuid.v4()}'})
        .select()
        .single();

    final apptRepo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 20)).copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0,
        );
    final appointment = await apptRepo.book(
      businessId: businessId,
      customerId: customer['id'] as String,
      staffId: staffId,
      startAt: startAt,
      endAt: startAt.add(const Duration(minutes: 60)),
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: serviceA['id'] as String,
          nameSnapshot: 'ignored -- server-derived',
          durationMinutes: 30,
          priceSnapshot: Decimal.parse('1'),
        ),
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: serviceB['id'] as String,
          nameSnapshot: 'ignored -- server-derived',
          durationMinutes: 30,
          priceSnapshot: Decimal.parse('1'),
        ),
      ],
    );

    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CONFIRMED');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CHECKED_IN');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'COMPLETED');

    final treatments = await client
        .from('treatment_history')
        .select('service_id, staff_id, customer_id, service_name_snapshot, appointment_id')
        .eq('appointment_id', appointment.id)
        .order('created_at');
    expect((treatments as List), hasLength(2));
    final serviceIds = treatments.map((t) => (t as Map)['service_id']).toSet();
    expect(serviceIds, {serviceA['id'], serviceB['id']});
    for (final t in treatments) {
      expect((t as Map)['customer_id'], customer['id']);
      expect(t['staff_id'], staffId);
    }
    final names = treatments.map((t) => (t as Map)['service_name_snapshot']).toSet();
    expect(names, {serviceA['name'], serviceB['name']});

    // Repeated completion: the state machine itself rejects a second
    // COMPLETED transition (COMPLETED is terminal) -- confirms no
    // duplicate treatment rows can be produced by a retried call.
    await expectLater(
      apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'COMPLETED'),
      throwsA(isA<PostgrestException>()),
    );
    final treatmentsAfterRetry = await client
        .from('treatment_history')
        .select('id')
        .eq('appointment_id', appointment.id);
    expect((treatmentsAfterRetry as List), hasLength(2));
  });

  test('customer treatment history: correct tenant records only, chronological (newest first), '
      'no cross-customer leakage', () async {
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

    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'History Order Service ${_uuid.v4()}', 'price': 60000})
        .select()
        .single();
    final customer1 = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'History Customer 1 ${_uuid.v4()}'})
        .select()
        .single();
    final customer2 = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'History Customer 2 ${_uuid.v4()}'})
        .select()
        .single();

    final repo = TreatmentHistoryRepository(client);
    final earlier = await repo.create(
      businessId: businessId,
      customerId: customer1['id'] as String,
      serviceId: service['id'] as String,
      staffId: staffId,
      treatmentDate: DateTime.now().subtract(const Duration(days: 2)),
    );
    final later = await repo.create(
      businessId: businessId,
      customerId: customer1['id'] as String,
      serviceId: service['id'] as String,
      staffId: staffId,
      treatmentDate: DateTime.now(),
    );
    await repo.create(
      businessId: businessId,
      customerId: customer2['id'] as String,
      serviceId: service['id'] as String,
      staffId: staffId,
      treatmentDate: DateTime.now(),
    );

    final history = await repo.listForCustomer(businessId, customer1['id'] as String);
    expect(history.length, greaterThanOrEqualTo(2));
    expect(history.every((t) => t.customerId == customer1['id']), isTrue);
    final ids = history.map((t) => t.id).toList();
    expect(ids.contains(earlier.id) && ids.contains(later.id), isTrue);
    // Newest first.
    final laterIndex = ids.indexOf(later.id);
    final earlierIndex = ids.indexOf(earlier.id);
    expect(laterIndex, lessThan(earlierIndex));
  });
}
