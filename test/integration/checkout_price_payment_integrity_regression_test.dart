// Live regression coverage for Day 7 findings F7-1, F7-2, F7-3 (see
// supabase/migrations/0024_complete_sale_price_and_payment_integrity.sql).
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/checkout_price_payment_integrity_regression_test.dart
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
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0024 applied and seeded with the QA fixture accounts.';

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

  group('F7-1: authoritative price enforcement', () {
    test('a forged low unit_price for a SERVICE is ignored; the catalog price (and its commission) is used', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final ownerAId = client.auth.currentUser!.id;

      final service = await client
          .from('services')
          .insert({
            'business_id': businessAId,
            'name': 'F7-1 Service Price Test ${_uuid.v4()}',
            'price': 200000,
            'commission_value': 10,
          })
          .select()
          .single();

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': ownerAId,
            'name_snapshot': 'Forged price attempt',
            'quantity': 1,
            'unit_price': '1', // forged: real catalog price is 200000
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '200000', // must cover the REAL total to succeed under F7-2
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('200000'), reason: 'sale total must reflect the catalog price, not the forged unit_price');

      final saleItem = await client.from('sale_items').select('unit_price, subtotal, commission_amount').eq('sale_id', sale['id'] as String).single();
      expect(Decimal.parse(saleItem['unit_price'].toString()), Decimal.parse('200000'));
      expect(Decimal.parse(saleItem['subtotal'].toString()), Decimal.parse('200000'));
      expect(Decimal.parse(saleItem['commission_amount'].toString()), Decimal.parse('20000'), reason: '10% commission must be computed off the real 200,000 price, not the forged 1');

      await client.auth.signOut();
    });

    test('a forged unit_price for a PRODUCT is ignored; the catalog selling_price is used', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      final product = await client
          .from('products')
          .insert({
            'business_id': businessAId,
            'name': 'F7-1 Product Price Test ${_uuid.v4()}',
            'selling_price': 50000,
            'stock_quantity': 10,
          })
          .select()
          .single();

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'PRODUCT',
            'service_id': null,
            'product_id': product['id'],
            'staff_id': null,
            'name_snapshot': 'Forged price attempt',
            'quantity': 2,
            'unit_price': '999999', // forged: real catalog price is 50000
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '100000', // 2 x real 50,000
        idempotencyKey: _uuid.v4(),
      );

      expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('100000'), reason: 'sale total must reflect 2 x the catalog selling_price, not the forged unit_price');

      final saleItem = await client.from('sale_items').select('unit_price, subtotal').eq('sale_id', sale['id'] as String).single();
      expect(Decimal.parse(saleItem['unit_price'].toString()), Decimal.parse('50000'));

      await client.auth.signOut();
    });
  });

  group('F7-2: payment must cover the total', () {
    test('paid_amount = 0 is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-2 Zero Paid Test ${_uuid.v4()}', 'price': 200000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      await expectLater(
        posRepo.completeSale(
          businessId: businessAId,
          branchId: branchId,
          customerId: null,
          items: [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F7-2 Zero Paid Test',
              'quantity': 1,
              'unit_price': '200000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '0',
          idempotencyKey: _uuid.v4(),
        ),
        // Phase 3 (0043) added a more specific zero-amount guard ahead of
        // the total-comparison guard this test originally targeted -- a
        // paid_amount of exactly 0 now hits that check first. The sale is
        // still correctly rejected either way; only the message changed.
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Payment amount must be greater than zero'))),
      );

      final noSale = await client.from('sales').select('id').eq('business_id', businessAId).eq('subtotal', 200000).eq('paid_amount', 0);
      expect(noSale, isEmpty, reason: 'a rejected sale must leave no partial row behind');

      await client.auth.signOut();
    });

    test('paid_amount one unit below the total is rejected', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-2 Underpaid Test ${_uuid.v4()}', 'price': 200000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      await expectLater(
        posRepo.completeSale(
          businessId: businessAId,
          branchId: branchId,
          customerId: null,
          items: [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F7-2 Underpaid Test',
              'quantity': 1,
              'unit_price': '200000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '199999',
          idempotencyKey: _uuid.v4(),
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Payment amount cannot be less than the sale total'))),
      );

      await client.auth.signOut();
    });

    test('paid_amount exactly equal to the total succeeds with zero change', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-2 Exact Paid Test ${_uuid.v4()}', 'price': 200000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F7-2 Exact Paid Test',
            'quantity': 1,
            'unit_price': '200000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '200000',
        idempotencyKey: _uuid.v4(),
      );

      expect(sale['status'], 'COMPLETED');
      expect(sale['payment_status'], 'COMPLETED');
      expect(Decimal.parse(sale['change_amount'].toString()), Decimal.zero);

      await client.auth.signOut();
    });

    test('an overpayment succeeds with the correct change', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-2 Overpaid Test ${_uuid.v4()}', 'price': 200000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);

      final sale = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'F7-2 Overpaid Test',
            'quantity': 1,
            'unit_price': '200000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '250000',
        idempotencyKey: _uuid.v4(),
      );

      expect(sale['status'], 'COMPLETED');
      expect(Decimal.parse(sale['change_amount'].toString()), Decimal.parse('50000'));

      await client.auth.signOut();
    });
  });

  group('F7-3: mandatory idempotency key', () {
    test('a NULL idempotency key is rejected by the database, not just the client', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-3 Null Key Test ${_uuid.v4()}', 'price': 10000})
          .select()
          .single();

      // Bypasses PosRepository (which always sends a real key) to call the
      // RPC directly with p_idempotency_key omitted, proving the guard is
      // enforced at the RPC/database boundary, not merely by the app.
      await expectLater(
        client.rpc('complete_sale', params: {
          'p_business_id': businessAId,
          'p_branch_id': null,
          'p_customer_id': null,
          'p_items': [
            {
              'item_type': 'SERVICE',
              'service_id': service['id'],
              'product_id': null,
              'staff_id': null,
              'name_snapshot': 'F7-3 Null Key Test',
              'quantity': 1,
              'unit_price': '10000',
              'discount_amount': '0',
            },
          ],
          'p_discount_amount': '0',
          'p_tax_amount': '0',
          'p_payment_method': 'CASH',
          'p_paid_amount': '10000',
          'p_idempotency_key': null,
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Idempotency key is required'))),
      );

      await client.auth.signOut();
    });

    test('a repeated valid idempotency key returns the existing sale, not a duplicate', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final service = await client
          .from('services')
          .insert({'business_id': businessAId, 'name': 'F7-3 Duplicate Key Test ${_uuid.v4()}', 'price': 10000})
          .select()
          .single();
      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final key = _uuid.v4();
      final items = [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': 'F7-3 Duplicate Key Test',
          'quantity': 1,
          'unit_price': '10000',
          'discount_amount': '0',
        },
      ];

      final first = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: items,
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '10000',
        idempotencyKey: key,
      );

      final second = await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: items,
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '10000',
        idempotencyKey: key,
      );

      expect(second['id'], first['id'], reason: 'a retried submit with the same key must return the original sale, not create a new one');

      final matches = await client.from('sales').select('id').eq('business_id', businessAId).eq('idempotency_key', key);
      expect(matches, hasLength(1));

      await client.auth.signOut();
    });
  });
}
