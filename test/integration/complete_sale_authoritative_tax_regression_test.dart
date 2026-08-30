// Live regression coverage for F9-6-1 (final security/release gap audit
// -- see supabase/migrations/0029_complete_sale_authoritative_tax.sql).
//
// complete_sale previously trusted p_tax_amount verbatim from the client
// for both sales.tax_amount and sales.total_amount -- F7-1 (Day 7) made
// unit_price authoritative the same way price forgery was closed, but tax
// was never given the same treatment. This file proves the exploit is
// closed: tax is now derived server-side from the target business's own
// tax_enabled/tax_rate, and a forged p_tax_amount can no longer influence
// either the persisted tax_amount or the payment-sufficiency check.
//
// Uses the same live Supabase project and QA fixture account as the other
// integration tests in this directory:
//   - van@test.local / admin123456@ -- OWNER of business "A"
//
// Business A's tax settings are read, temporarily changed via the
// existing update_business_settings RPC (F9-4, no direct table write),
// and restored to their exact original values at the end of every test
// that touches them -- the same round-trip discipline already
// established in the F9-3/F9-4 regression suites. No new business or
// member is created.
//
// Rounding: complete_sale's round(numeric, 2) call mirrors the exact
// convention already used for commission calculation in the same
// function. A dedicated .xx5-boundary test was considered and skipped --
// engineering an exact halfway case through the full item-price ->
// subtotal -> discount -> taxable-base pipeline adds fragile complexity
// for what is now a UX-only concern (the server is authoritative; the
// client's own preview no longer affects what is persisted).
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/complete_sale_authoritative_tax_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0029 applied and seeded with the QA fixture accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Future<void> _setTax(SupabaseClient client, Business original, String businessId, {required bool enabled, required double rate}) async {
  await BusinessRepository(client).updateSettings(
    businessId: businessId,
    name: original.name,
    phone: original.phone,
    email: original.email,
    address: original.address,
    currency: original.currency,
    taxEnabled: enabled,
    taxRate: rate,
    logoUrl: original.logoUrl,
  );
}

Future<void> _restoreTax(SupabaseClient client, Business original, String businessId) async {
  await _setTax(client, original, businessId, enabled: original.taxEnabled, rate: original.taxRate);
}

Future<Map<String, dynamic>> _createService(SupabaseClient client, String businessId, num price) async {
  return await client
      .from('services')
      .insert({'business_id': businessId, 'name': 'F9-6-1 Fixture Service ${_uuid.v4()}', 'price': price})
      .select()
      .single();
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('tax-enabled: a forged p_tax_amount=0 is ignored -- persisted tax is the server-computed 10%, and total requires the real payment', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 100000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      final sale = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F9-6-1 forged-zero-tax attempt',
            'quantity': 1,
            'unit_price': '100000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0', // forged: real tax is 10% of 100000 = 10000
        paymentMethod: 'CASH',
        paidAmount: '110000', // covers the REAL total, not the forged one
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['tax_amount'].toString()), Decimal.parse('10000'),
          reason: 'server must compute 10% tax regardless of the forged p_tax_amount=0');
      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('110000'));
      expect(Decimal.parse(sale['total_amount'].toString()),
          Decimal.parse(sale['subtotal'].toString()) - Decimal.parse(sale['discount_amount'].toString()) + Decimal.parse(sale['tax_amount'].toString()));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('tax-enabled: an inflated forged p_tax_amount is ignored -- persisted tax and total remain the server-computed values', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 50000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      final sale = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F9-6-1 inflated-tax attempt',
            'quantity': 1,
            'unit_price': '50000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '999999', // forged: real tax is 10% of 50000 = 5000
        paymentMethod: 'CASH',
        paidAmount: '55000',
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['tax_amount'].toString()), Decimal.parse('5000'));
      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('55000'));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('tax-disabled: a forged non-zero p_tax_amount is ignored -- persisted tax is zero and total carries no tax', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: false, rate: 0);
    try {
      final service = await _createService(client, businessId, 20000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      final sale = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F9-6-1 tax-disabled forged-tax attempt',
            'quantity': 1,
            'unit_price': '20000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '5000', // forged: business has tax disabled
        paymentMethod: 'CASH',
        paidAmount: '20000',
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['tax_amount'].toString()), Decimal.zero);
      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('20000'));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('payment integrity: a paid_amount sufficient only for the forged (tax-free) total is rejected against the real server total', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 100000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      // Forged tax=0 implies a (wrong) total of 100000; the real total is
      // 110000. paid_amount covers only the forged total, so the server's
      // authoritative-total check must reject it.
      await expectLater(
        posRepo.completeSale(
          businessId: businessId,
          branchId: branchId,
          customerId: null,
          items: [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F9-6-1 payment-boundary attempt',
              'quantity': 1,
              'unit_price': '100000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '100000',
          idempotencyKey: _uuid.v4(),
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Payment amount cannot be less than the sale total'))),
      );
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('idempotency remains intact under the new tax logic: a repeated idempotency key returns the original sale, not a duplicate', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 10000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);
      final key = _uuid.v4();
      final items = [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': 'F9-6-1 idempotency check',
          'quantity': 1,
          'unit_price': '10000',
          'discount_amount': '0',
        },
      ];

      final first = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: items,
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '11000',
        idempotencyKey: key,
      );
      final second = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: items,
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '11000',
        idempotencyKey: key,
      );

      expect(second['id'], first['id']);
      final allSalesForKey = await client.from('sales').select('id').eq('business_id', businessId).eq('idempotency_key', key);
      expect(allSalesForKey, hasLength(1));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('F7-1 price integrity still holds alongside the new authoritative tax: a forged unit_price is ignored and the catalog price drives both subtotal and tax', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 200000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      final sale = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F9-6-1 combined price+tax forgery attempt',
            'quantity': 1,
            'unit_price': '1', // forged: real catalog price is 200000
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0', // also forged
        paymentMethod: 'CASH',
        paidAmount: '220000', // must cover the REAL total (200000 + 10%) to succeed
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['subtotal'].toString()), Decimal.parse('200000'), reason: 'catalog price, not the forged unit_price');
      expect(Decimal.parse(sale['tax_amount'].toString()), Decimal.parse('20000'), reason: '10% of the real catalog subtotal, not the forged tax');
      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('220000'));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });

  test('audit integrity: exactly one PAYMENT audit row, correct actor/business/entity, new_data carries the server-derived tax and total', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final membership = (await BusinessRepository(client).myMemberships()).firstWhere((m) => m.role == BusinessRole.owner);
    final businessId = membership.business.id;
    final ownerId = client.auth.currentUser!.id;
    final original = membership.business;

    await _setTax(client, original, businessId, enabled: true, rate: 10);
    try {
      final service = await _createService(client, businessId, 30000);
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessId);

      final sale = await posRepo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F9-6-1 audit check',
            'quantity': 1,
            'unit_price': '30000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '33000',
        idempotencyKey: _uuid.v4(),
      );
      final saleId = sale['id'] as String;

      final auditRows = await client
          .from('audit_logs')
          .select()
          .eq('business_id', businessId)
          .eq('action', 'PAYMENT')
          .eq('entity_type', 'sale')
          .eq('entity_id', saleId);
      expect(auditRows, hasLength(1));
      final audit = auditRows[0];
      expect(audit['user_id'], ownerId);
      final newData = audit['new_data'] as Map;
      expect(Decimal.parse(newData['tax_amount'].toString()), Decimal.parse('3000'));
      expect(Decimal.parse(newData['total_amount'].toString()), Decimal.parse('33000'));
    } finally {
      await _restoreTax(client, original, businessId);
    }

    await client.auth.signOut();
  });
}
