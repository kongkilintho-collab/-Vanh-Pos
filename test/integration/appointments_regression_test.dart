// Live regression coverage for Phase 1 (Appointment / Calendar) --
// supabase/migrations/0030_appointments_schema.sql and
// 0031_appointment_rpcs.sql.
//
// Covers the three properties the architecture depends on:
//   1) appointments/appointment_items have no direct-write RLS policy --
//      a CASHIER+ direct INSERT is denied, exactly like sales/sale_items
//      after 0025 (see direct_insert_rls_regression_test.dart).
//   2) book_appointment succeeds for a CASHIER+ caller and a second
//      booking for the same staff member with an overlapping time range is
//      rejected by the appointments_no_staff_overlap exclusion constraint.
//   3) set_appointment_status enforces its state machine -- a
//      SCHEDULED -> COMPLETED jump is rejected; the SCHEDULED -> CONFIRMED
//      -> CHECKED_IN -> COMPLETED path succeeds.
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/appointments_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/appointments/data/appointment_repository.dart';
import 'package:beauty_clinic_pos/shared/models/appointment_item.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:decimal/decimal.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0030/0031 applied and seeded with the QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Matcher _deniedByRls() => isA<PostgrestException>().having(
      (e) => e.code,
      'code',
      '42501',
    );

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('a direct INSERT into appointments is denied by RLS', () async {
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
    final userId = client.auth.currentUser!.id;

    final now = DateTime.now().toUtc();
    await expectLater(
      client.from('appointments').insert({
        'business_id': businessId,
        'staff_id': userId,
        'start_at': now.toIso8601String(),
        'end_at': now.add(const Duration(minutes: 30)).toIso8601String(),
      }),
      throwsA(_deniedByRls()),
    );
  });

  test('book_appointment succeeds and a second overlapping booking for the same staff is rejected', () async {
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
        .insert({'business_id': businessId, 'name': 'Appt Test Facial', 'price': 150000, 'duration_minutes': 60})
        .select()
        .single();

    final repo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 1)).copyWith(
          hour: 10,
          minute: 0,
          second: 0,
          microsecond: 0,
          millisecond: 0,
        );
    final endAt = startAt.add(const Duration(minutes: 60));

    final item = AppointmentItem(
      id: '',
      appointmentId: '',
      serviceId: service['id'] as String,
      nameSnapshot: service['name'] as String,
      durationMinutes: 60,
      priceSnapshot: Decimal.parse('150000'),
    );

    final first = await repo.book(
      businessId: businessId,
      staffId: staffId,
      startAt: startAt,
      endAt: endAt,
      items: [item],
      notes: 'Regression test booking ${_uuid.v4()}',
    );
    expect(first.id, isNotEmpty);
    expect(first.items, hasLength(1));

    // Overlaps the first booking by 30 minutes for the same staff member.
    final overlappingStart = startAt.add(const Duration(minutes: 30));
    final overlappingEnd = overlappingStart.add(const Duration(minutes: 60));

    await expectLater(
      repo.book(
        businessId: businessId,
        staffId: staffId,
        startAt: overlappingStart,
        endAt: overlappingEnd,
        items: [item],
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('set_appointment_status enforces the SCHEDULED->CONFIRMED->CHECKED_IN->COMPLETED state machine', () async {
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
        .insert({'business_id': businessId, 'name': 'Appt Test Massage', 'price': 100000, 'duration_minutes': 45})
        .select()
        .single();

    final repo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 2)).copyWith(
          hour: 14,
          minute: 0,
          second: 0,
          microsecond: 0,
          millisecond: 0,
        );
    final endAt = startAt.add(const Duration(minutes: 45));

    final appointment = await repo.book(
      businessId: businessId,
      staffId: staffId,
      startAt: startAt,
      endAt: endAt,
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: service['id'] as String,
          nameSnapshot: service['name'] as String,
          durationMinutes: 45,
          priceSnapshot: Decimal.parse('100000'),
        ),
      ],
    );

    // Jumping straight to COMPLETED is not a valid transition from SCHEDULED.
    await expectLater(
      repo.setStatus(
        businessId: businessId,
        appointmentId: appointment.id,
        status: 'COMPLETED',
      ),
      throwsA(isA<PostgrestException>()),
    );

    final confirmed = await repo.setStatus(
      businessId: businessId,
      appointmentId: appointment.id,
      status: 'CONFIRMED',
    );
    expect(confirmed.status.dbValue, 'CONFIRMED');

    final checkedIn = await repo.setStatus(
      businessId: businessId,
      appointmentId: appointment.id,
      status: 'CHECKED_IN',
    );
    expect(checkedIn.status.dbValue, 'CHECKED_IN');

    final completed = await repo.setStatus(
      businessId: businessId,
      appointmentId: appointment.id,
      status: 'COMPLETED',
    );
    expect(completed.status.dbValue, 'COMPLETED');
  });
}
