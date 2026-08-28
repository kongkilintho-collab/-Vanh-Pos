// Live regression coverage for Day 2's complete_sale RPC (see
// supabase/migrations/0017_pos_checkout.sql): the atomic POS checkout
// transaction. Uses the same live Supabase project and QA fixture
// accounts as test/integration/business_repository_regression_test.dart —
// see that file's header for setup details and the skip-when-unconfigured
// behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/pos_checkout_regression_test.dart
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
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided — run with '
    '--dart-define-from-file=env.json against a project with '
    '0017_pos_checkout.sql applied and seeded with the QA fixture accounts.';

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

  test('CASHIER-or-above can complete a mixed service+product sale, atomically', () async {
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

    // Minimal fixture data for this test only.
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Checkout Test Facial', 'price': 200000, 'commission_value': 10})
        .select()
        .single();
    final product = await client
        .from('products')
        .insert({'business_id': businessId, 'name': 'Checkout Test Serum', 'selling_price': 50000, 'stock_quantity': 5})
        .select()
        .single();
    final stockBefore = product['stock_quantity'] as int;

    final repo = PosRepository(client);
    final branchId = await repo.primaryBranchId(businessId);
    final idempotencyKey = _uuid.v4();

    final sale = await repo.completeSale(
      businessId: businessId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': 'Checkout Test Facial',
          'quantity': 1,
          'unit_price': '200000',
          'discount_amount': '0',
        },
        {
          'item_type': 'PRODUCT',
          'service_id': null,
          'product_id': product['id'],
          'staff_id': null,
          'name_snapshot': 'Checkout Test Serum',
          'quantity': 2,
          'unit_price': '50000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '300000',
      idempotencyKey: idempotencyKey,
    );

    expect(Decimal.parse(sale['total_amount'].toString()), Decimal.parse('300000'));
    expect(sale['status'], 'COMPLETED');
    expect(sale['payment_status'], 'COMPLETED');

    // Inventory decremented for the product line.
    final productAfter =
        await client.from('products').select('stock_quantity').eq('id', product['id']).single();
    expect(productAfter['stock_quantity'], stockBefore - 2);

    final movements = await client
        .from('inventory_movements')
        .select()
        .eq('reference_type', 'sale')
        .eq('reference_id', sale['id']);
    expect(movements, isNotEmpty);
    expect((movements as List).first['quantity'], -2);

    // Audit log written for the sale.
    final audit = await client
        .from('audit_logs')
        .select()
        .eq('entity_type', 'sale')
        .eq('entity_id', sale['id']);
    expect(audit, isNotEmpty);

    await client.auth.signOut();
  });

  test('idempotency key makes a retried submit a no-op, not a duplicate sale', () async {
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
        .insert({'business_id': businessId, 'name': 'Idempotency Test Service', 'price': 100000})
        .select()
        .single();

    final repo = PosRepository(client);
    final branchId = await repo.primaryBranchId(businessId);
    final idempotencyKey = _uuid.v4();
    final items = [
      {
        'item_type': 'SERVICE',
        'service_id': service['id'],
        'product_id': null,
        'staff_id': null,
        'name_snapshot': 'Idempotency Test Service',
        'quantity': 1,
        'unit_price': '100000',
        'discount_amount': '0',
      },
    ];

    final first = await repo.completeSale(
      businessId: businessId,
      branchId: branchId,
      customerId: null,
      items: items,
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '100000',
      idempotencyKey: idempotencyKey,
    );

    final second = await repo.completeSale(
      businessId: businessId,
      branchId: branchId,
      customerId: null,
      items: items,
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '100000',
      idempotencyKey: idempotencyKey,
    );

    expect(second['id'], first['id'], reason: 'a retried submit with the same idempotency key must return the original sale, not create a new one');

    final matchingSales = await client
        .from('sales')
        .select('id')
        .eq('business_id', businessId)
        .eq('idempotency_key', idempotencyKey);
    expect(matchingSales, hasLength(1));

    await client.auth.signOut();
  });

  test('insufficient stock is rejected and the sale is not created', () async {
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

    final product = await client
        .from('products')
        .insert({'business_id': businessId, 'name': 'Low Stock Test Product', 'selling_price': 10000, 'stock_quantity': 1})
        .select()
        .single();

    final repo = PosRepository(client);
    final branchId = await repo.primaryBranchId(businessId);

    await expectLater(
      repo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'PRODUCT',
            'service_id': null,
            'product_id': product['id'],
            'staff_id': null,
            'name_snapshot': 'Low Stock Test Product',
            'quantity': 5,
            'unit_price': '10000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '50000',
        idempotencyKey: _uuid.v4(),
      ),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient stock'))),
    );

    final productAfter =
        await client.from('products').select('stock_quantity').eq('id', product['id']).single();
    expect(productAfter['stock_quantity'], 1, reason: 'stock must be unchanged when the sale is rejected');

    await client.auth.signOut();
  });

  test('a non-member cannot record a sale for a business they do not belong to', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;

    // A synthetic business id that corresponds to no business at all, so it
    // can never coincide with a membership User A happens to hold (unlike a
    // real fixture business, which User A may have since been added to).
    final nonMemberBusinessId = _uuid.v4();

    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final repo = PosRepository(client);

    await expectLater(
      repo.completeSale(
        businessId: nonMemberBusinessId,
        branchId: null,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': null,
            'product_id': null,
            'staff_id': null,
            'name_snapshot': 'Unauthorized attempt',
            'quantity': 1,
            'unit_price': '1',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '1',
        idempotencyKey: _uuid.v4(),
      ),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
    );

    await client.auth.signOut();
  });
}
