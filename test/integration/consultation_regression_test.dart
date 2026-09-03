// Live regression coverage for Phase 5 (Consultation / Customer
// Consultation Records) -- supabase/migrations/0048_consultations.sql:
// the consultations table, create_consultation_record RPC.
//
// Follows the same live QA project / fixture-account pattern as
// treatment_history_regression_test.dart. Two lessons from that file's
// own post-hoc corrections are applied directly here rather than
// repeated:
//   1) the identity-protection test mutates staff_id to a genuinely
//      DIFFERENT value (a second real staff/business-member id), never
//      the same value the row already had (same-value writes are a
//      harmless SQL no-op under IS DISTINCT FROM, not a bypass, and
//      asserting rejection on one would be a false-positive-prone test).
//   2) the cross-tenant SELECT check is not asserted as "must return
//      empty" against admin@test.local, because that account is a real,
//      legitimate ADMIN member of Business A in this QA project (see
//      business_members) -- both fixture accounts in this project are
//      dual-business members, so no single-business-only account exists
//      to validly test pure RLS SELECT denial. This is documented as a
//      fixture limitation, not silently skipped or misreported as a pass.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/consultation_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/customers/data/consultation_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0048 applied and seeded with the QA fixture accounts.';
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

  test('valid consultation creation (walk-in, no appointment): server-derives snapshots, '
      'required fields enforced, audit log created, ordering, narrative update, '
      'identity protection with a genuinely different value, direct INSERT/DELETE denied', () async {
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
    final secondStaffProfile = await client
        .from('profiles')
        .select('id')
        .neq('id', staffId)
        .limit(1)
        .maybeSingle();

    final realServiceName = 'Consultation Test Service ${_uuid.v4()}';
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': realServiceName, 'price': 100000})
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'Consultation Test Customer ${_uuid.v4()}'})
        .select()
        .single();

    final repo = ConsultationRepository(client);

    // Required-field enforcement: server rejects a missing customer.
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessId,
        'p_customer_id': '00000000-0000-0000-0000-000000000000',
        'p_staff_id': staffId,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Server-derived snapshots: creation sends no name, and a recommended
    // service is included to prove that snapshot too.
    final record = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      staffId: staffId,
      consultationDate: DateTime.now(),
      recommendedServiceId: service['id'] as String,
      consultationNotes: 'Initial consult notes',
      customerConcerns: 'Dry skin',
      observations: 'Mild redness',
      considerations: 'Sensitive to fragrance',
      assessment: 'Good candidate',
      recommendationNotes: 'Recommend hydrating facial',
    );
    expect(record.staffId, staffId);
    expect(record.recommendedServiceNameSnapshot, realServiceName);
    expect(record.appointmentId, isNull);
    expect(record.customerId, customer['id']);

    // Audit log created, exactly once.
    final auditRows = await client
        .from('audit_logs')
        .select('id, action, entity_type, entity_id')
        .eq('entity_type', 'consultation')
        .eq('entity_id', record.id);
    expect((auditRows as List), hasLength(1));
    expect((auditRows.first as Map)['action'], 'CREATE');

    // Direct read via RLS.
    final direct = await client.from('consultations').select().eq('id', record.id).single();
    expect(direct['recommended_service_name_snapshot'], realServiceName);
    expect(direct['recommended_service_id'], service['id']);

    // Direct DELETE denied (no policy exists at all).
    final deleted = await client.from('consultations').delete().eq('id', record.id).select();
    expect((deleted as List), isEmpty);
    final stillThere = await client.from('consultations').select('id').eq('id', record.id).single();
    expect(stillThere['id'], record.id);

    // Identity field cannot be altered via direct UPDATE -- using a
    // GENUINELY DIFFERENT staff id, not the same one the row already has.
    if (secondStaffProfile != null) {
      await expectLater(
        client.from('consultations').update({'staff_id': secondStaffProfile['id']}).eq('id', record.id).select(),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify identity or snapshot fields'),
        )),
      );
    }
    // consultation_date is also identity-protected -- verify with a
    // genuinely different value too.
    await expectLater(
      client
          .from('consultations')
          .update({'consultation_date': '2020-01-01T00:00:00Z'})
          .eq('id', record.id)
          .select(),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Cannot modify identity or snapshot fields'),
      )),
    );

    // Narrative fields CAN be updated (authorized, CASHIER+ owner).
    await repo.updateNarrative(id: record.id, consultationNotes: 'Updated notes', assessment: 'Revised assessment');
    final afterUpdate = await client
        .from('consultations')
        .select('consultation_notes, assessment')
        .eq('id', record.id)
        .single();
    expect(afterUpdate['consultation_notes'], 'Updated notes');
    expect(afterUpdate['assessment'], 'Revised assessment');

    // Ordering: a second, more recent consultation for the same customer
    // must come first.
    final later = await repo.create(
      businessId: businessId,
      customerId: customer['id'] as String,
      staffId: staffId,
      consultationDate: DateTime.now().add(const Duration(minutes: 1)),
    );
    final history = await repo.listForCustomer(businessId, customer['id'] as String);
    expect(history.first.id, later.id);
  });

  test('a direct INSERT into consultations is denied by RLS', () async {
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
      client.from('consultations').insert({
        'business_id': businessId,
        'customer_id': '00000000-0000-0000-0000-000000000000',
        'staff_id': '00000000-0000-0000-0000-000000000000',
        'staff_name_snapshot': 'x',
        'consultation_date': DateTime.now().toUtc().toIso8601String(),
      }),
      throwsA(_deniedByRls()),
    );
  });

  test('anon EXECUTE on create_consultation_record is denied', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await client.auth.signOut();
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': '00000000-0000-0000-0000-000000000000',
        'p_customer_id': '00000000-0000-0000-0000-000000000000',
        'p_staff_id': '00000000-0000-0000-0000-000000000000',
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
  });

  test('role authorization: CASHIER+ successfully creates a consultation record '
      '(no STAFF/CASHIER-below fixture exists to test denial live)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    markTestSkipped(_noStaffCashierFixture);
  });

  test('tenant isolation: customer/staff/appointment/recommended-service from another business are '
      'all rejected; appointment/customer mismatch is rejected; cross-tenant SELECT has a '
      'documented fixture limitation', () async {
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
        .insert({'business_id': businessIdA, 'name': 'Tenant Consult Service A ${_uuid.v4()}', 'price': 50000})
        .select()
        .single();
    final customerA = await client
        .from('customers')
        .insert({'business_id': businessIdA, 'name': 'Tenant Consult Customer A ${_uuid.v4()}'})
        .select()
        .single();
    final otherCustomerA = await client
        .from('customers')
        .insert({'business_id': businessIdA, 'name': 'Tenant Consult Customer A2 ${_uuid.v4()}'})
        .select()
        .single();

    // Appointment/customer mismatch: create a real appointment for
    // otherCustomerA, then attempt a consultation for customerA supplying
    // that appointment_id.
    final apptForOther = await client.rpc('book_appointment', params: {
      'p_business_id': businessIdA,
      'p_branch_id': null,
      'p_customer_id': otherCustomerA['id'],
      'p_staff_id': staffIdA,
      'p_start_at': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      'p_end_at': DateTime.now().toUtc().add(const Duration(days: 30, minutes: 30)).toIso8601String(),
      'p_items': [
        {
          'service_id': serviceA['id'],
          'name_snapshot': 'ignored',
          'duration_minutes': 30,
          'price_snapshot': '1',
        },
      ],
      'p_notes': null,
    }) as Map<String, dynamic>;

    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessIdA,
        'p_customer_id': customerA['id'],
        'p_staff_id': staffIdA,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': apptForOther['id'],
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('does not belong to the selected customer'),
      )),
    );

    final recordA = await ConsultationRepository(client).create(
      businessId: businessIdA,
      customerId: customerA['id'] as String,
      staffId: staffIdA,
      consultationDate: DateTime.now(),
    );

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner && m.business.id != businessIdA)
        .business
        .id;

    // Cross-tenant customer: Business B scoped to its own business_id, but
    // targeting Business A's real customer -- rejected.
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerA['id'],
        'p_staff_id': staffIdA,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Customer not found'))),
    );

    // Cross-tenant service: Business B's own customer, but Business A's
    // real recommended_service_id -- rejected.
    final customerB = await client
        .from('customers')
        .insert({'business_id': businessIdB, 'name': 'Tenant Consult Customer B ${_uuid.v4()}'})
        .select()
        .single();
    final staffIdB = client.auth.currentUser!.id;
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerB['id'],
        'p_staff_id': staffIdB,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_recommended_service_id': serviceA['id'],
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('Recommended service not found'),
      )),
    );

    // Cross-tenant appointment: Business B's own customer, but Business
    // A's real appointment_id -- rejected.
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerB['id'],
        'p_staff_id': staffIdB,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': apptForOther['id'],
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Appointment not found'))),
    );

    // Cross-tenant staff: Business B's own customer, but Business A's
    // staff id (not a member of B).
    await expectLater(
      client.rpc('create_consultation_record', params: {
        'p_business_id': businessIdB,
        'p_customer_id': customerB['id'],
        'p_staff_id': staffIdA,
        'p_consultation_date': DateTime.now().toUtc().toIso8601String(),
        'p_appointment_id': null,
        'p_recommended_service_id': null,
        'p_consultation_notes': null,
        'p_customer_concerns': null,
        'p_observations': null,
        'p_considerations': null,
        'p_assessment': null,
        'p_recommendation_notes': null,
      }),
      throwsA(isA<PostgrestException>().having(
        (e) => e.message,
        'message',
        contains('not an active member'),
      )),
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
}
