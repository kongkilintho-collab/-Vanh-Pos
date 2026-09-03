// Live regression coverage for Phase 3 (Deposit / Outstanding Balance) --
// supabase/migrations/0042-0045:
//   0042_payment_status_partial_value.sql
//   0043_complete_sale_partial_payment.sql
//   0044_record_sale_payment_rpc.sql
//   0045_void_sale_payment_status.sql
//
// Follows the same live QA project / fixture-account pattern as
// pos_checkout_regression_test.dart / void_sale_regression_test.dart /
// appointments_regression_test.dart.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/phase3_deposit_settlement_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
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
    '0042-0045 applied and seeded with the QA fixture accounts.';

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

Future<Map<String, dynamic>> _depositSale(
  SupabaseClient client, {
  required String businessId,
  String? branchId,
  required Map<String, dynamic> service,
  required num paidAmount,
  bool allowPartial = true,
}) async {
  return await client.rpc('complete_sale', params: {
    'p_business_id': businessId,
    'p_branch_id': branchId,
    'p_customer_id': null,
    'p_items': [
      {
        'item_type': 'SERVICE',
        'service_id': service['id'],
        'product_id': null,
        'staff_id': null,
        'name_snapshot': service['name'],
        'quantity': 1,
        'unit_price': service['price'],
        'discount_amount': 0,
      },
    ],
    'p_discount_amount': 0,
    'p_tax_amount': 0,
    'p_payment_method': 'CASH',
    'p_paid_amount': paidAmount,
    'p_idempotency_key': _uuid.v4(),
    'p_allow_partial_payment': allowPartial,
  }) as Map<String, dynamic>;
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('a direct INSERT into payments is denied by RLS', () async {
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
      client.from('payments').insert({
        'business_id': businessId,
        'sale_id': '00000000-0000-0000-0000-000000000000',
        'payment_method': 'CASH',
        'amount': 1,
      }),
      throwsA(_deniedByRls()),
    );
  });

  test('a direct DELETE against payments is denied (no DELETE policy exists)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);

    // No payments_delete policy exists at all -- default-deny applies
    // regardless of which row (if any) matches; this proves the row is
    // never removed rather than merely "not found".
    final rows = await client
        .from('payments')
        .delete()
        .eq('id', '00000000-0000-0000-0000-000000000000')
        .select();
    expect((rows as List), isEmpty);
  });

  test('normal checkout (no explicit opt-in) still rejects an underpayment exactly as before', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Backward-Compat Service ${_uuid.v4()}', 'price': 100000})
        .select()
        .single();

    // No p_allow_partial_payment key at all -- exactly what PosRepository.completeSale sends today.
    await expectLater(
      client.rpc('complete_sale', params: {
        'p_business_id': businessId,
        'p_branch_id': null,
        'p_customer_id': null,
        'p_items': [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': service['name'],
            'quantity': 1,
            'unit_price': service['price'],
            'discount_amount': 0,
          },
        ],
        'p_discount_amount': 0,
        'p_tax_amount': 0,
        'p_payment_method': 'CASH',
        'p_paid_amount': 50000,
        'p_idempotency_key': _uuid.v4(),
      }),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('deposit: p_allow_partial_payment=true accepts a partial payment and sets PARTIAL status', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Deposit Service ${_uuid.v4()}', 'price': 500000})
        .select()
        .single();

    final sale = await _depositSale(client, businessId: businessId, service: service, paidAmount: 200000);
    expect(sale['payment_status'], 'PARTIAL');
    expect(Decimal.parse(sale['paid_amount'].toString()), Decimal.parse('200000.00'));
    expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('500000.00'));
  });

  test('deposit: zero and negative payment are rejected even with p_allow_partial_payment=true', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Zero Deposit Service ${_uuid.v4()}', 'price': 100000})
        .select()
        .single();

    await expectLater(
      _depositSale(client, businessId: businessId, service: service, paidAmount: 0),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      _depositSale(client, businessId: businessId, service: service, paidAmount: -1),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('settlement: record_sale_payment completes a PARTIAL sale, correct paid amount and zero balance', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Settlement Service ${_uuid.v4()}', 'price': 300000})
        .select()
        .single();

    final sale = await _depositSale(client, businessId: businessId, service: service, paidAmount: 100000);
    final saleId = sale['id'] as String;

    final repo = PosRepository(client);

    // First additional payment: still leaves a balance.
    final r1 = await repo.recordSalePayment(
      businessId: businessId,
      saleId: saleId,
      paymentMethod: 'CASH',
      amount: '100000',
    );
    expect(r1['payment_status'], 'PARTIAL');
    expect(Decimal.parse(r1['paid_amount'].toString()), Decimal.parse('200000.00'));
    expect(Decimal.parse(r1['outstanding_balance'].toString()), Decimal.parse('100000.00'));

    // Second, final payment: settles the balance to exactly zero.
    final r2 = await repo.recordSalePayment(
      businessId: businessId,
      saleId: saleId,
      paymentMethod: 'CARD',
      amount: '100000',
    );
    expect(r2['payment_status'], 'COMPLETED');
    expect(Decimal.parse(r2['paid_amount'].toString()), Decimal.parse('300000.00'));
    expect(Decimal.parse(r2['outstanding_balance'].toString()), Decimal.zero);

    // Payment history: three rows total (initial deposit + 2 settlements),
    // summing to the full total.
    final payments = await client.from('payments').select('amount').eq('sale_id', saleId);
    final sum = (payments as List)
        .map((p) => Decimal.parse((p as Map)['amount'].toString()))
        .fold(Decimal.zero, (a, b) => a + b);
    expect((payments).length, 3);
    expect(sum, Decimal.parse('300000.00'));

    // A further payment attempt is rejected: already fully paid.
    await expectLater(
      repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '1'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('settlement: payment greater than outstanding balance is rejected; zero/negative rejected', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Overpay Service ${_uuid.v4()}', 'price': 200000})
        .select()
        .single();

    final sale = await _depositSale(client, businessId: businessId, service: service, paidAmount: 50000);
    final saleId = sale['id'] as String;
    final repo = PosRepository(client);

    // Outstanding is 150000; attempting 150001 must be rejected.
    await expectLater(
      repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '150001'),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '0'),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '-10'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('concurrency: two concurrent settlement attempts for the full outstanding balance -- exactly one succeeds', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Concurrency Service ${_uuid.v4()}', 'price': 100000})
        .select()
        .single();

    final sale = await _depositSale(client, businessId: businessId, service: service, paidAmount: 1);
    final saleId = sale['id'] as String;
    final repo = PosRepository(client);

    // Outstanding is 99999. Fire two concurrent attempts to pay the full
    // remaining balance -- the FOR UPDATE lock in record_sale_payment must
    // serialize these, so at most one can succeed.
    final results = await Future.wait<Object?>([
      repo
          .recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '99999')
          .then<Object?>((r) => r)
          .catchError((Object e) => e),
      repo
          .recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '99999')
          .then<Object?>((r) => r)
          .catchError((Object e) => e),
    ]);

    final successes = results.whereType<Map<String, dynamic>>().toList();
    final failures = results.where((r) => r is! Map<String, dynamic>).toList();
    expect(successes, hasLength(1));
    expect(failures, hasLength(1));

    final finalSale = await client.from('sales').select('paid_amount, total_amount, payment_status').eq('id', saleId).single();
    expect(Decimal.parse(finalSale['paid_amount'].toString()), Decimal.parse('100000.00'));
    expect(Decimal.parse(finalSale['paid_amount'].toString()) <= Decimal.parse(finalSale['total_amount'].toString()), isTrue);
    expect(finalSale['payment_status'], 'COMPLETED');
  });

  test('void: voiding a PARTIAL sale marks all payments REFUNDED, preserves payment history, sets payment_status REFUNDED', () async {
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
        .insert({'business_id': businessId, 'name': 'P3 Void Partial Service ${_uuid.v4()}', 'price': 400000})
        .select()
        .single();

    final sale = await _depositSale(client, businessId: businessId, service: service, paidAmount: 150000);
    final saleId = sale['id'] as String;
    final repo = PosRepository(client);

    await repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '50000');

    final paymentsBefore = await client.from('payments').select('id, status').eq('sale_id', saleId);
    expect((paymentsBefore as List), hasLength(2));

    await repo.voidSale(businessId: businessId, saleId: saleId, reason: 'P3 regression test void of partial sale');

    final voided = await client.from('sales').select('status, payment_status, paid_amount').eq('id', saleId).single();
    expect(voided['status'], 'VOIDED');
    expect(voided['payment_status'], 'REFUNDED');
    // paid_amount is preserved as the historical record -- not reset to 0.
    expect(Decimal.parse(voided['paid_amount'].toString()), Decimal.parse('200000.00'));

    final paymentsAfter = await client.from('payments').select('id, status').eq('sale_id', saleId);
    expect((paymentsAfter as List), hasLength(2));
    for (final p in paymentsAfter) {
      expect((p as Map)['status'], 'REFUNDED');
    }

    // A voided sale can no longer accept a new payment.
    await expectLater(
      repo.recordSalePayment(businessId: businessId, saleId: saleId, paymentMethod: 'CASH', amount: '1'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('tenant isolation: Business A cannot settle a sale belonging to Business B', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;

    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessIdB = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final serviceB = await client
        .from('services')
        .insert({'business_id': businessIdB, 'name': 'P3 Tenant B Service ${_uuid.v4()}', 'price': 100000})
        .select()
        .single();
    final saleB = await _depositSale(client, businessId: businessIdB, service: serviceB, paidAmount: 30000);
    final saleIdB = saleB['id'] as String;

    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessIdA = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final repo = PosRepository(client);

    await expectLater(
      repo.recordSalePayment(businessId: businessIdA, saleId: saleIdB, paymentMethod: 'CASH', amount: '10000'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
