// Live regression coverage for the P1-01 fix --
// supabase/migrations/0041_book_appointment_authoritative_price.sql.
//
// Confirmed finding (Phase 1-2 Post-Implementation Forensic Audit): before
// this migration, book_appointment persisted appointment_items.
// name_snapshot/price_snapshot verbatim from client-supplied p_items, and
// Phase 2's set_appointment_status used that untrusted price for
// PERCENTAGE commission calculation on package-redeemed sessions -- the
// same defect class already fixed for complete_sale's unit_price in
// 0024_complete_sale_price_and_payment_integrity.sql (F7-1).
//
// This file does NOT modify appointments_regression_test.dart or
// packages_regression_test.dart (both already cover normal booking,
// double-booking, the status state machine, and the full package-redemption
// happy path -- that existing coverage stands in for "Test E: existing
// valid booking still works"). It adds only the four new authority-specific
// cases the P1-01 fix requires:
//   A) a forged client price_snapshot is ignored; the real services.price
//      is persisted instead.
//   B) a forged client name_snapshot is ignored; the real services.name is
//      persisted instead.
//   C) PERCENTAGE commission on a package-redeemed session is computed from
//      the authoritative persisted price, not a forged one -- proving the
//      full book_appointment -> appointment_items -> set_appointment_status
//      chain is closed.
//   D) a service belonging to another business is rejected (tenant
//      isolation is unchanged by the new services lookup in the insert
//      loop).
//
// Same live QA project / fixture-account pattern as the other integration
// tests in this directory.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/p1_01_appointment_price_authority_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/appointments/data/appointment_repository.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/packages/data/customer_package_repository.dart';
import 'package:beauty_clinic_pos/features/packages/data/package_repository.dart';
import 'package:beauty_clinic_pos/shared/models/appointment_item.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/package.dart';
import 'package:beauty_clinic_pos/shared/models/package_item.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0041 applied and seeded with the QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('Test A: book_appointment ignores a forged client price_snapshot and persists the real service price', () async {
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
        .insert({
          'business_id': businessId,
          'name': 'P1-01 Price Test Service ${_uuid.v4()}',
          'price': 500000,
          'duration_minutes': 30,
        })
        .select()
        .single();

    final repo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 10)).copyWith(
          hour: 9, minute: 0, second: 0, microsecond: 0, millisecond: 0,
        );

    final appointment = await repo.book(
      businessId: businessId,
      staffId: staffId,
      startAt: startAt,
      endAt: startAt.add(const Duration(minutes: 30)),
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: service['id'] as String,
          nameSnapshot: service['name'] as String,
          durationMinutes: 30,
          // Forged: the real service price is 500000.
          priceSnapshot: Decimal.parse('100000'),
        ),
      ],
    );

    final persisted = await client
        .from('appointment_items')
        .select('price_snapshot')
        .eq('appointment_id', appointment.id)
        .single();
    expect(Decimal.parse(persisted['price_snapshot'].toString()), Decimal.parse('500000.00'));
  });

  test('Test B: book_appointment ignores a forged client name_snapshot and persists the real service name', () async {
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

    final realName = 'Actual Service ${_uuid.v4()}';
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': realName, 'price': 80000, 'duration_minutes': 30})
        .select()
        .single();

    final repo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 11)).copyWith(
          hour: 9, minute: 30, second: 0, microsecond: 0, millisecond: 0,
        );

    final appointment = await repo.book(
      businessId: businessId,
      staffId: staffId,
      startAt: startAt,
      endAt: startAt.add(const Duration(minutes: 30)),
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: service['id'] as String,
          // Forged: the real service name is realName.
          nameSnapshot: 'Fake Service',
          durationMinutes: 30,
          priceSnapshot: Decimal.parse('80000'),
        ),
      ],
    );

    final persisted = await client
        .from('appointment_items')
        .select('name_snapshot')
        .eq('appointment_id', appointment.id)
        .single();
    expect(persisted['name_snapshot'], realName);
  });

  test('Test C: PERCENTAGE commission on package redemption uses the authoritative service price, '
      'not a forged appointment price_snapshot', () async {
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

    // 20% PERCENTAGE commission, real price 500000 -> expected commission 100000.
    final service = await client
        .from('services')
        .insert({
          'business_id': businessId,
          'name': 'P1-01 Commission Test Service ${_uuid.v4()}',
          'price': 500000,
          'duration_minutes': 30,
          'commission_type': 'PERCENTAGE',
          'commission_value': 20,
        })
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'P1-01 Commission Test Customer ${_uuid.v4()}'})
        .select()
        .single();

    final packageRepo = PackageRepository(client);
    final package = await packageRepo.create(
      Package(
        id: '',
        businessId: businessId,
        name: 'P1-01 Commission Test Package ${_uuid.v4()}',
        price: Decimal.parse('500000'),
        active: true,
      ),
      [PackageItem(id: '', packageId: '', serviceId: service['id'] as String, sessionCount: 1)],
    );

    final customerPackageRepo = CustomerPackageRepository(client);
    final purchased = await customerPackageRepo.purchase(
      businessId: businessId,
      customerId: customer['id'] as String,
      packageId: package.id,
      paymentMethod: 'CASH',
      paidAmount: '500000',
      idempotencyKey: _uuid.v4(),
    );
    final entitlementItemId = purchased.items.first.id;

    final apptRepo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 12)).copyWith(
          hour: 13, minute: 0, second: 0, microsecond: 0, millisecond: 0,
        );
    final appointment = await apptRepo.book(
      businessId: businessId,
      customerId: customer['id'] as String,
      staffId: staffId,
      startAt: startAt,
      endAt: startAt.add(const Duration(minutes: 30)),
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: service['id'] as String,
          nameSnapshot: 'Fake Name',
          durationMinutes: 30,
          // Forged near-zero price: if this were trusted, commission would
          // round to 0 (20% of 1 = 0.20 rounded to 0.00), not 100000.
          priceSnapshot: Decimal.parse('1'),
          customerPackageItemId: entitlementItemId,
        ),
      ],
    );

    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CONFIRMED');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CHECKED_IN');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'COMPLETED');

    final redemptions = await client
        .from('customer_package_redemptions')
        .select('id')
        .eq('customer_package_item_id', entitlementItemId);
    expect((redemptions as List), hasLength(1));

    final commission = await client
        .from('commissions')
        .select('commission_amount')
        .eq('customer_package_redemption_id', (redemptions.first as Map)['id'])
        .single();
    // 20% of the REAL persisted price (500000) = 100000, proving the
    // forged 1 was never used for this calculation.
    expect(Decimal.parse(commission['commission_amount'].toString()), Decimal.parse('100000.00'));
  });

  test('Test D: book_appointment rejects a service belonging to another business', () async {
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

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final serviceB = await client
        .from('services')
        .insert({
          'business_id': businessIdB,
          'name': 'P1-01 Cross Tenant Service ${_uuid.v4()}',
          'price': 100000,
          'duration_minutes': 30,
        })
        .select()
        .single();

    // Sign back in as A and attempt to book using B's service id.
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final repo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 13)).copyWith(
          hour: 15, minute: 0, second: 0, microsecond: 0, millisecond: 0,
        );

    await expectLater(
      repo.book(
        businessId: businessIdA,
        staffId: staffIdA,
        startAt: startAt,
        endAt: startAt.add(const Duration(minutes: 30)),
        items: [
          AppointmentItem(
            id: '',
            appointmentId: '',
            serviceId: serviceB['id'] as String,
            nameSnapshot: 'x',
            durationMinutes: 30,
            priceSnapshot: Decimal.parse('100000'),
          ),
        ],
      ),
      throwsA(isA<PostgrestException>()),
    );
  });
}
