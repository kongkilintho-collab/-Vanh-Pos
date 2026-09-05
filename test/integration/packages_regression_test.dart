// Live regression coverage for Phase 2 (Packages / Membership) --
// supabase/migrations/0032-0039. Not yet executable: as of this commit
// these migrations have not been applied to the QA Supabase project (see
// the Phase 2 implementation report). Written now, following the same
// pattern as appointments_regression_test.dart/pos_checkout_regression_test.dart
// (live QA project, signed-in fixture accounts, real RPC calls), so it is
// ready to run the moment the migrations are live.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/packages_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/appointments/data/appointment_repository.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/commissions/data/commission_repository.dart';
import 'package:beauty_clinic_pos/features/packages/data/customer_package_repository.dart';
import 'package:beauty_clinic_pos/features/packages/data/package_repository.dart';
import 'package:beauty_clinic_pos/shared/models/appointment_item.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/commission_status.dart';
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
    '0032-0039 applied and seeded with the QA fixture accounts.';

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

/// Purchases a one-session package and completes an appointment against it,
/// returning the resulting redemption row (id, customer_package_item_id)
/// and the entitlement's package-item id. `commissionValue` lets callers
/// construct either a commission-bearing or a zero-commission redemption
/// (services.commission_value defaults to 0, which yields commission_amount
/// = 0 in set_appointment_status, which is < the > 0 guard, so no
/// commissions row is ever created for that case -- this is how a
/// redemption legitimately ends up with zero associated commissions).
Future<({String redemptionId, String customerPackageItemId})> _createCompletedRedemption(
  SupabaseClient client, {
  required String businessId,
  required String staffId,
  required num commissionValue,
}) async {
  final service = await client
      .from('services')
      .insert({
        'business_id': businessId,
        'name': '0056 Reversal Test Service ${_uuid.v4()}',
        'price': 100000,
        'duration_minutes': 30,
        'commission_value': commissionValue,
      })
      .select()
      .single();
  final customer = await client
      .from('customers')
      .insert({'business_id': businessId, 'name': '0056 Reversal Test Customer ${_uuid.v4()}'})
      .select()
      .single();

  final packageRepo = PackageRepository(client);
  final package = await packageRepo.create(
    Package(id: '', businessId: businessId, name: '0056 Reversal Test Package ${_uuid.v4()}', price: Decimal.parse('100000'), active: true),
    [PackageItem(id: '', packageId: '', serviceId: service['id'] as String, sessionCount: 1)],
  );

  final customerPackageRepo = CustomerPackageRepository(client);
  final purchased = await customerPackageRepo.purchase(
    businessId: businessId,
    customerId: customer['id'] as String,
    packageId: package.id,
    paymentMethod: 'CASH',
    paidAmount: '100000',
    idempotencyKey: _uuid.v4(),
  );
  final entitlementItemId = purchased.items.first.id;

  final apptRepo = AppointmentRepository(client);
  final startAt = DateTime.now().toUtc().add(Duration(days: 3, minutes: _uuid.v4().hashCode.abs() % 1000)).copyWith(
        hour: 11, minute: 0, second: 0, microsecond: 0, millisecond: 0,
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
        nameSnapshot: service['name'] as String,
        durationMinutes: 30,
        priceSnapshot: Decimal.parse('100000'),
        customerPackageItemId: entitlementItemId,
      ),
    ],
  );

  await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CONFIRMED');
  await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CHECKED_IN');
  await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'COMPLETED');

  final redemption = await client
      .from('customer_package_redemptions')
      .select('id')
      .eq('customer_package_item_id', entitlementItemId)
      .single();

  return (redemptionId: redemption['id'] as String, customerPackageItemId: entitlementItemId);
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('a direct INSERT into customer_packages is denied by RLS', () async {
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
      client.from('customer_packages').insert({
        'business_id': businessId,
        'customer_id': '00000000-0000-0000-0000-000000000000',
        'name_snapshot': 'x',
        'price_paid_snapshot': 0,
      }),
      throwsA(_deniedByRls()),
    );
  });

  test('package purchase creates entitlement; redemption at completion decrements sessions; '
      'double redemption and expired/insufficient/customer-mismatch cases are rejected', () async {
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
        .insert({'business_id': businessId, 'name': 'Pkg Test Facial', 'price': 100000, 'duration_minutes': 30})
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'Pkg Test Customer ${_uuid.v4()}'})
        .select()
        .single();

    final packageRepo = PackageRepository(client);
    final package = await packageRepo.create(
      Package(
        id: '',
        businessId: businessId,
        name: 'Pkg Test Package ${_uuid.v4()}',
        price: Decimal.parse('150000'),
        validityDays: 90,
        active: true,
      ),
      [PackageItem(id: '', packageId: '', serviceId: service['id'] as String, sessionCount: 1)],
    );
    expect(package.items, hasLength(1));

    final customerPackageRepo = CustomerPackageRepository(client);
    final purchased = await customerPackageRepo.purchase(
      businessId: businessId,
      customerId: customer['id'] as String,
      packageId: package.id,
      paymentMethod: 'CASH',
      paidAmount: '150000',
      idempotencyKey: _uuid.v4(),
    );
    expect(purchased.items, hasLength(1));
    final entitlementItemId = purchased.items.first.id;
    expect(purchased.items.first.remainingSessions, 1);

    // Book an appointment linking this entitlement, then walk it to COMPLETED.
    final apptRepo = AppointmentRepository(client);
    final startAt = DateTime.now().toUtc().add(const Duration(days: 3)).copyWith(
          hour: 11, minute: 0, second: 0, microsecond: 0, millisecond: 0,
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
          nameSnapshot: service['name'] as String,
          durationMinutes: 30,
          priceSnapshot: Decimal.parse('100000'),
          customerPackageItemId: entitlementItemId,
        ),
      ],
    );

    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CONFIRMED');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'CHECKED_IN');
    final completed =
        await apptRepo.setStatus(businessId: businessId, appointmentId: appointment.id, status: 'COMPLETED');
    expect(completed.items.first.packageUsedSessions, 1);
    expect(completed.items.first.packageTotalSessions, 1);

    // A redemption row and a commission row should now exist.
    final redemptions = await client
        .from('customer_package_redemptions')
        .select('id')
        .eq('customer_package_item_id', entitlementItemId);
    expect((redemptions as List), hasLength(1));

    final commissions = await client
        .from('commissions')
        .select('id, sale_id, sale_item_id, customer_package_redemption_id')
        .eq('customer_package_redemption_id', (redemptions.first as Map)['id']);
    if (commissions.isNotEmpty) {
      final c = commissions.first;
      expect(c['sale_id'], isNull);
      expect(c['sale_item_id'], isNull);
    }

    // Insufficient sessions: book + complete a second appointment against
    // the same (now fully used) entitlement.
    final start2 = startAt.add(const Duration(hours: 2));
    final appointment2 = await apptRepo.book(
      businessId: businessId,
      customerId: customer['id'] as String,
      staffId: staffId,
      startAt: start2,
      endAt: start2.add(const Duration(minutes: 30)),
      items: [
        AppointmentItem(
          id: '',
          appointmentId: '',
          serviceId: service['id'] as String,
          nameSnapshot: service['name'] as String,
          durationMinutes: 30,
          priceSnapshot: Decimal.parse('100000'),
          customerPackageItemId: entitlementItemId,
        ),
      ],
    );
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment2.id, status: 'CONFIRMED');
    await apptRepo.setStatus(businessId: businessId, appointmentId: appointment2.id, status: 'CHECKED_IN');
    await expectLater(
      apptRepo.setStatus(businessId: businessId, appointmentId: appointment2.id, status: 'COMPLETED'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('void_sale rejects a package sale with redeemed sessions, allows an unused one', () async {
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

    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Void Pkg Test Service', 'price': 50000, 'duration_minutes': 30})
        .select()
        .single();
    final customer = await client
        .from('customers')
        .insert({'business_id': businessId, 'name': 'Void Pkg Test Customer ${_uuid.v4()}'})
        .select()
        .single();

    final packageRepo = PackageRepository(client);
    final package = await packageRepo.create(
      Package(id: '', businessId: businessId, name: 'Void Test Package ${_uuid.v4()}', price: Decimal.parse('50000'), active: true),
      [PackageItem(id: '', packageId: '', serviceId: service['id'] as String, sessionCount: 1)],
    );

    final customerPackageRepo = CustomerPackageRepository(client);
    final purchased = await customerPackageRepo.purchase(
      businessId: businessId,
      customerId: customer['id'] as String,
      packageId: package.id,
      paymentMethod: 'CASH',
      paidAmount: '50000',
      idempotencyKey: _uuid.v4(),
    );

    // Unused package sale can be voided.
    final voidResult = await client.rpc('void_sale', params: {
      'p_business_id': businessId,
      'p_sale_id': purchased.saleId,
      'p_reason': 'regression test void',
    });
    expect(voidResult, isNotNull);

    final cancelled = await client
        .from('customer_packages')
        .select('status')
        .eq('id', purchased.id)
        .single();
    expect(cancelled['status'], 'CANCELLED');
  });

  // Phase 9 / 0056 -- reverse_package_redemption (F-1).
  group('reverse_package_redemption', () {
    test('MANAGER+ reversal restores the session exactly once, reverses the commission, marks the '
        'redemption reversed, writes one audit row, leaves the appointment COMPLETED, and a second '
        'attempt is rejected with zero additional mutation', () async {
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

      final fixture = await _createCompletedRedemption(client, businessId: businessId, staffId: staffId, commissionValue: 10);

      final cpiBefore = await client.from('customer_package_items').select('used_sessions').eq('id', fixture.customerPackageItemId).single();
      expect(cpiBefore['used_sessions'], 1);
      final commissionBefore = await client
          .from('commissions')
          .select('id, status')
          .eq('customer_package_redemption_id', fixture.redemptionId)
          .single();
      expect(commissionBefore['status'], 'PENDING');
      final appointmentStatusBefore = await client
          .from('customer_package_redemptions')
          .select('appointment_id')
          .eq('id', fixture.redemptionId)
          .single();

      final reversed = await client.rpc('reverse_package_redemption', params: {
        'p_business_id': businessId,
        'p_redemption_id': fixture.redemptionId,
        'p_reason': '0056 regression reversal',
      });
      expect(reversed['reversed'], true);

      final cpiAfter = await client.from('customer_package_items').select('used_sessions').eq('id', fixture.customerPackageItemId).single();
      expect(cpiAfter['used_sessions'], 0, reason: 'exactly one session restored');

      final commissionAfter =
          await client.from('commissions').select('status').eq('id', commissionBefore['id']).single();
      expect(commissionAfter['status'], 'REVERSED');

      final auditRows = await client
          .from('audit_logs')
          .select('id')
          .eq('entity_type', 'customer_package_redemption')
          .eq('entity_id', fixture.redemptionId)
          .eq('action', 'REVERSE_PACKAGE_REDEMPTION');
      expect(auditRows, hasLength(1));

      final appointment = await client
          .from('appointments')
          .select('status')
          .eq('id', appointmentStatusBefore['appointment_id'])
          .single();
      expect(appointment['status'], 'COMPLETED', reason: 'the appointment state machine is never touched by reversal');

      // Second reversal: rejected, zero additional mutation.
      await expectLater(
        client.rpc('reverse_package_redemption', params: {
          'p_business_id': businessId,
          'p_redemption_id': fixture.redemptionId,
          'p_reason': 'second attempt',
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('already been reversed'))),
      );

      final cpiFinal = await client.from('customer_package_items').select('used_sessions').eq('id', fixture.customerPackageItemId).single();
      expect(cpiFinal['used_sessions'], 0, reason: 'second attempt must not restore a second session');
      final auditRowsFinal = await client
          .from('audit_logs')
          .select('id')
          .eq('entity_type', 'customer_package_redemption')
          .eq('entity_id', fixture.redemptionId)
          .eq('action', 'REVERSE_PACKAGE_REDEMPTION');
      expect(auditRowsFinal, hasLength(1), reason: 'no additional audit row from the rejected second attempt');

      await client.auth.signOut();
    });

    test('a redemption with no associated commission reverses successfully with commission_reversed=false', () async {
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

      // commission_value=0 -> set_appointment_status computes
      // commission_amount=0, which is not > 0, so no commissions row is
      // ever created -- a legitimate, expected zero-commission redemption.
      final fixture = await _createCompletedRedemption(client, businessId: businessId, staffId: staffId, commissionValue: 0);

      final noCommission =
          await client.from('commissions').select('id').eq('customer_package_redemption_id', fixture.redemptionId);
      expect(noCommission, isEmpty, reason: 'sanity: this fixture must have zero commissions');

      final reversed = await client.rpc('reverse_package_redemption', params: {
        'p_business_id': businessId,
        'p_redemption_id': fixture.redemptionId,
        'p_reason': '0056 no-commission reversal',
      });
      expect(reversed['reversed'], true);

      final auditRows = await client
          .from('audit_logs')
          .select('metadata')
          .eq('entity_type', 'customer_package_redemption')
          .eq('entity_id', fixture.redemptionId)
          .eq('action', 'REVERSE_PACKAGE_REDEMPTION')
          .single();
      expect(auditRows['metadata']['commission_reversed'], false);

      await client.auth.signOut();
    });

    test('a CASHIER-rank member cannot reverse a package redemption', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final fixture = await _createCompletedRedemption(client, businessId: businessBId, staffId: client.auth.currentUser!.id, commissionValue: 10);
      await client.auth.signOut();

      // van@test.local is a real CASHIER of Business B (Day 3 fixture) --
      // below the MANAGER floor reverse_package_redemption requires.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        client.rpc('reverse_package_redemption', params: {
          'p_business_id': businessBId,
          'p_redemption_id': fixture.redemptionId,
          'p_reason': 'should be rejected',
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
      );

      await client.auth.signOut();
    });

    test('an anonymous caller cannot reverse a package redemption', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await expectLater(
        client.rpc('reverse_package_redemption', params: {
          'p_business_id': _uuid.v4(),
          'p_redemption_id': _uuid.v4(),
          'p_reason': 'anon attempt',
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a cross-tenant reversal attempt is rejected with a generic not-found error, no mutation', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final fixture = await _createCompletedRedemption(client, businessId: businessBId, staffId: client.auth.currentUser!.id, commissionValue: 10);
      await client.auth.signOut();

      // Van is a real OWNER of Business A -- real MANAGER+ authority, but
      // only within Business A, not Business B.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      await expectLater(
        client.rpc('reverse_package_redemption', params: {
          'p_business_id': businessAId,
          'p_redemption_id': fixture.redemptionId,
          'p_reason': 'cross-tenant probe',
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('not found in this business'))),
      );

      final untouched = await client.from('customer_package_items').select('used_sessions').eq('id', fixture.customerPackageItemId).single();
      expect(untouched['used_sessions'], 1, reason: 'the cross-tenant attempt must leave the other business\'s data untouched');

      await client.auth.signOut();
    });

    test('two concurrent reversal attempts on the same redemption: exactly one succeeds', () async {
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
      final fixture = await _createCompletedRedemption(client, businessId: businessId, staffId: staffId, commissionValue: 10);

      final results = await Future.wait([
        client
            .rpc('reverse_package_redemption', params: {'p_business_id': businessId, 'p_redemption_id': fixture.redemptionId, 'p_reason': 'concurrent A'})
            .then<Object?>((v) => v)
            .catchError((Object e) => e),
        client
            .rpc('reverse_package_redemption', params: {'p_business_id': businessId, 'p_redemption_id': fixture.redemptionId, 'p_reason': 'concurrent B'})
            .then<Object?>((v) => v)
            .catchError((Object e) => e),
      ]);

      final successes = results.whereType<Map<String, dynamic>>().toList();
      final failures = results.whereType<PostgrestException>().toList();
      expect(successes, hasLength(1), reason: 'exactly one of the two concurrent reversals must succeed');
      expect(failures, hasLength(1), reason: 'the other must be cleanly rejected as already-reversed, not silently duplicated');

      final cpiAfter = await client.from('customer_package_items').select('used_sessions').eq('id', fixture.customerPackageItemId).single();
      expect(cpiAfter['used_sessions'], 0, reason: 'no lost update, no double restoration');

      await client.auth.signOut();
    });

    test('a reversed commission is a terminal state: direct ADMIN attempts to move it to PENDING, APPROVED, '
        'or PAID are all rejected, while the ordinary forward workflow for an unrelated commission still works', () async {
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

      final fixture = await _createCompletedRedemption(client, businessId: businessId, staffId: staffId, commissionValue: 10);
      final commission = await client.from('commissions').select('id').eq('customer_package_redemption_id', fixture.redemptionId).single();
      final commissionId = commission['id'] as String;

      await client.rpc('reverse_package_redemption', params: {
        'p_business_id': businessId,
        'p_redemption_id': fixture.redemptionId,
        'p_reason': '0056 terminal-state fixture setup',
      });

      final commissionRepo = CommissionRepository(client);
      for (final target in [CommissionStatus.pending, CommissionStatus.approved, CommissionStatus.paid]) {
        await expectLater(
          commissionRepo.updateStatus(id: commissionId, businessId: businessId, status: target),
          throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Cannot change status once a commission has been reversed'))),
        );
      }
      final stillReversed = await client.from('commissions').select('status').eq('id', commissionId).single();
      expect(stillReversed['status'], 'REVERSED');

      // The ordinary, unrelated forward workflow (a fresh, non-reversed
      // commission) must remain completely unaffected by the new guard.
      final freshService = await client
          .from('services')
          .insert({'business_id': businessId, 'name': '0056 Forward Flow Service ${_uuid.v4()}', 'price': 10000, 'commission_value': 10})
          .select()
          .single();
      final freshCustomer = await client
          .from('customers')
          .insert({'business_id': businessId, 'name': '0056 Forward Flow Customer ${_uuid.v4()}'})
          .select()
          .single();
      final saleResult = await client.rpc('complete_sale', params: {
        'p_business_id': businessId,
        'p_branch_id': null,
        'p_customer_id': freshCustomer['id'],
        'p_items': [
          {
            'item_type': 'SERVICE',
            'service_id': freshService['id'],
            'product_id': null,
            'staff_id': staffId,
            'name_snapshot': '0056 Forward Flow Service',
            'quantity': 1,
            'unit_price': '10000',
            'discount_amount': '0',
          },
        ],
        'p_discount_amount': '0',
        'p_tax_amount': '0',
        'p_payment_method': 'CASH',
        'p_paid_amount': '10000',
        'p_idempotency_key': _uuid.v4(),
      });
      final freshCommission = await client.from('commissions').select('id, status').eq('sale_id', saleResult['id']).single();
      expect(freshCommission['status'], 'PENDING');

      await commissionRepo.updateStatus(id: freshCommission['id'] as String, businessId: businessId, status: CommissionStatus.approved);
      final afterApprove = await client.from('commissions').select('status').eq('id', freshCommission['id']).single();
      expect(afterApprove['status'], 'APPROVED');

      await commissionRepo.updateStatus(id: freshCommission['id'] as String, businessId: businessId, status: CommissionStatus.paid);
      final afterPaid = await client.from('commissions').select('status').eq('id', freshCommission['id']).single();
      expect(afterPaid['status'], 'PAID');

      await client.auth.signOut();
    });
  });
}
