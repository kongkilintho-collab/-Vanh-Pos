// Live regression coverage for Day 8 findings F8-1 through F8-5 (see
// supabase/migrations/0025_revoke_direct_financial_insert_paths.sql).
//
// Demonstrates the exact distinction the audit is about: an authenticated,
// correctly-role-qualified caller (CASHIER+/MANAGER+ as appropriate) is
// still DENIED by RLS when attempting a direct table INSERT on
// sales/sale_items/payments/commissions/inventory_movements, while the
// same caller's calls through complete_sale()/adjust_stock() (SECURITY
// DEFINER, unaffected by the removed policies) continue to succeed.
//
// Uses the same live Supabase project and QA fixture accounts as the
// other integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/direct_insert_rls_regression_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/inventory/data/inventory_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/inventory_movement_type.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0025 applied and seeded with the QA fixture accounts.';

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

  test('F8-1: a CASHIER+ direct INSERT into sales is denied by RLS', () async {
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

    await expectLater(
      client.from('sales').insert({
        'business_id': businessAId,
        'cashier_id': ownerAId,
        'subtotal': '10000',
        'total_amount': '10000',
        'paid_amount': '10000',
        'status': 'COMPLETED',
        'payment_status': 'COMPLETED',
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('F8-2: a CASHIER+ direct INSERT into sale_items (injecting a fake line into a real sale) is denied by RLS', () async {
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
        .insert({'business_id': businessAId, 'name': 'F8-2 Fixture Service ${_uuid.v4()}', 'price': 10000})
        .select()
        .single();
    final posRepo = PosRepository(client);
    final branchId = await posRepo.primaryBranchId(businessAId);
    final realSale = await posRepo.completeSale(
      businessId: businessAId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': 'F8-2 Fixture Service',
          'quantity': 1,
          'unit_price': '10000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '10000',
      idempotencyKey: _uuid.v4(),
    );

    await expectLater(
      client.from('sale_items').insert({
        'business_id': businessAId,
        'sale_id': realSale['id'] as String,
        'item_type': 'SERVICE',
        'service_id': service['id'],
        'name_snapshot': 'Retroactively injected line',
        'quantity': 1,
        'unit_price': '999999',
        'subtotal': '999999',
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('F8-3: an ADMIN+ direct INSERT into commissions is denied by RLS', () async {
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

    // A real sale with a PRODUCT line (no commission attached by
    // complete_sale, so the sale_item_id's uniqueness constraint on
    // commissions can't itself explain a rejection here -- isolating the
    // test to the RLS denial specifically).
    final product = await client
        .from('products')
        .insert({'business_id': businessAId, 'name': 'F8-3 Fixture Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
        .select()
        .single();
    final posRepo = PosRepository(client);
    final branchId = await posRepo.primaryBranchId(businessAId);
    final realSale = await posRepo.completeSale(
      businessId: businessAId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'PRODUCT',
          'service_id': null,
          'product_id': product['id'],
          'staff_id': null,
          'name_snapshot': 'F8-3 Fixture Product',
          'quantity': 1,
          'unit_price': '10000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '10000',
      idempotencyKey: _uuid.v4(),
    );
    final realSaleItem = await client.from('sale_items').select('id').eq('sale_id', realSale['id'] as String).single();

    await expectLater(
      client.from('commissions').insert({
        'business_id': businessAId,
        'sale_id': realSale['id'] as String,
        'sale_item_id': realSaleItem['id'] as String,
        'staff_id': ownerAId,
        'commission_type': 'PERCENTAGE',
        'commission_amount': '999999',
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('F8-4: a CASHIER+ direct INSERT into payments is denied by RLS', () async {
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
        .insert({'business_id': businessAId, 'name': 'F8-4 Fixture Service ${_uuid.v4()}', 'price': 10000})
        .select()
        .single();
    final posRepo = PosRepository(client);
    final branchId = await posRepo.primaryBranchId(businessAId);
    final realSale = await posRepo.completeSale(
      businessId: businessAId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': 'F8-4 Fixture Service',
          'quantity': 1,
          'unit_price': '10000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '10000',
      idempotencyKey: _uuid.v4(),
    );

    await expectLater(
      client.from('payments').insert({
        'business_id': businessAId,
        'sale_id': realSale['id'] as String,
        'payment_method': 'CASH',
        'amount': '50000',
        'created_by': ownerAId,
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('F8-5: a MANAGER+ direct INSERT into inventory_movements is denied by RLS', () async {
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
        .insert({'business_id': businessAId, 'name': 'F8-5 Fixture Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
        .select()
        .single();

    await expectLater(
      client.from('inventory_movements').insert({
        'business_id': businessAId,
        'product_id': product['id'],
        'movement_type': 'ADJUSTMENT',
        'quantity': 5,
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('legitimate paths remain functional: complete_sale() still succeeds after the INSERT policies are removed', () async {
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
        .insert({'business_id': businessAId, 'name': 'Legit Path Service ${_uuid.v4()}', 'price': 25000})
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
          'name_snapshot': 'Legit Path Service',
          'quantity': 1,
          'unit_price': '25000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '25000',
      idempotencyKey: _uuid.v4(),
    );

    expect(sale['status'], 'COMPLETED');
    final saleItems = await client.from('sale_items').select('id').eq('sale_id', sale['id'] as String);
    expect(saleItems, hasLength(1));
    final payments = await client.from('payments').select('id').eq('sale_id', sale['id'] as String);
    expect(payments, hasLength(1));

    await client.auth.signOut();
  });

  test('legitimate paths remain functional: adjust_stock() still succeeds after the INSERT policies are removed', () async {
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
        .insert({'business_id': businessAId, 'name': 'Legit Path Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
        .select()
        .single();

    final repo = InventoryRepository(client);
    await repo.adjustStock(
      businessId: businessAId,
      productId: product['id'] as String,
      movementType: InventoryMovementType.purchase,
      quantityDelta: 3,
    );

    final after = await client.from('products').select('stock_quantity').eq('id', product['id'] as String).single();
    expect(after['stock_quantity'], 8);

    final movement = await client.from('inventory_movements').select('id').eq('product_id', product['id'] as String).eq('reference_type', 'manual_adjustment');
    expect(movement, hasLength(1));

    await client.auth.signOut();
  });
}
