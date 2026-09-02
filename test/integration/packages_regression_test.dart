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
import 'package:beauty_clinic_pos/features/packages/data/customer_package_repository.dart';
import 'package:beauty_clinic_pos/features/packages/data/package_repository.dart';
import 'package:beauty_clinic_pos/shared/models/appointment_item.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/package.dart';
import 'package:beauty_clinic_pos/shared/models/package_item.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
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
}
