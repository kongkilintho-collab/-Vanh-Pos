// Live regression coverage for Day 4: the adjust_stock RPC (see
// supabase/migrations/0020_inventory_stock_adjustment.sql), the stock
// movements ledger, suppliers, and expense tracking.
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/inventory_expenses_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/expenses/data/expense_repository.dart';
import 'package:beauty_clinic_pos/features/inventory/data/inventory_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';
import 'package:beauty_clinic_pos/shared/models/expense.dart';
import 'package:beauty_clinic_pos/shared/models/inventory_movement_type.dart';
import 'package:beauty_clinic_pos/shared/models/payment_method.dart';
import 'package:beauty_clinic_pos/shared/models/supplier.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0020_inventory_stock_adjustment.sql applied and seeded with the QA '
    'fixture accounts.';

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

  group('Inventory', () {
    test('OWNER (MANAGER+) can restock a product; the movement and stock stay consistent', () async {
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
          .insert({'business_id': businessAId, 'name': 'Restock Test Product ${_uuid.v4()}', 'selling_price': 30000, 'stock_quantity': 5, 'minimum_stock': 2})
          .select()
          .single();
      final productId = product['id'] as String;

      final repo = InventoryRepository(client);
      await repo.adjustStock(
        businessId: businessAId,
        productId: productId,
        movementType: InventoryMovementType.purchase,
        quantityDelta: 10,
        note: 'Restock regression test',
      );

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 15, reason: 'stock must reflect the +10 adjustment atomically');

      final movements = await client
          .from('inventory_movements')
          .select()
          .eq('product_id', productId)
          .eq('reference_type', 'manual_adjustment');
      expect(movements, hasLength(1));
      final movement = (movements as List).first as Map<String, dynamic>;
      expect(movement['movement_type'], 'PURCHASE');
      expect(movement['quantity'], 10);

      await client.auth.signOut();
    });

    test('an adjustment that would take stock below zero is rejected, and stock is unchanged', () async {
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
          .insert({'business_id': businessAId, 'name': 'Negative Stock Test Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 2})
          .select()
          .single();
      final productId = product['id'] as String;

      final repo = InventoryRepository(client);
      await expectLater(
        repo.adjustStock(
          businessId: businessAId,
          productId: productId,
          movementType: InventoryMovementType.damage,
          quantityDelta: -5,
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('below zero stock'))),
      );

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 2, reason: 'stock must be unchanged when the adjustment is rejected');

      final movements = await client.from('inventory_movements').select('id').eq('product_id', productId);
      expect(movements, isEmpty, reason: 'no movement row should exist for a rejected adjustment');

      await client.auth.signOut();
    });

    test('the RPC rejects SALE as a manual movement type', () async {
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
          .insert({'business_id': businessAId, 'name': 'Sale Guard Test Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
          .select()
          .single();

      final repo = InventoryRepository(client);
      await expectLater(
        repo.adjustStock(
          businessId: businessAId,
          productId: product['id'] as String,
          movementType: InventoryMovementType.sale,
          quantityDelta: -1,
        ),
        throwsA(isA<PostgrestException>().having(
          (e) => e.message,
          'message',
          contains('SALE movements can only be recorded by complete_sale'),
        )),
      );

      await client.auth.signOut();
    });

    test('a CASHIER-rank member cannot adjust stock', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // Business B belongs to User B; User A is a real CASHIER there (Day 3
      // fixture). CASHIER is below the MANAGER floor adjust_stock enforces.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final product = await client
          .from('products')
          .insert({'business_id': businessBId, 'name': 'Cashier Guard Test Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
          .select()
          .single();
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final repo = InventoryRepository(client);
      await expectLater(
        repo.adjustStock(
          businessId: businessBId,
          productId: product['id'] as String,
          movementType: InventoryMovementType.adjustment,
          quantityDelta: 1,
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
      );

      await client.auth.signOut();
    });

    test('a product from another business cannot be adjusted, even by a real MANAGER+', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // A real product that belongs to Business B.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final productInB = await client
          .from('products')
          .insert({'business_id': businessBId, 'name': 'Cross Tenant Test Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 5})
          .select()
          .single();
      await client.auth.signOut();

      // User A is OWNER of Business A -- real MANAGER+ authority, but only
      // within Business A, not Business B.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;

      final repo = InventoryRepository(client);
      await expectLater(
        repo.adjustStock(
          businessId: businessAId,
          productId: productInB['id'] as String,
          movementType: InventoryMovementType.adjustment,
          quantityDelta: 1,
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Product not found in this business'))),
      );

      await client.auth.signOut();
    });

    test('the movements ledger and cross-tenant read isolation', () async {
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
          .insert({'business_id': businessAId, 'name': 'Ledger Test Product ${_uuid.v4()}', 'selling_price': 10000, 'stock_quantity': 0})
          .select()
          .single();

      final repo = InventoryRepository(client);
      await repo.adjustStock(
        businessId: businessAId,
        productId: product['id'] as String,
        movementType: InventoryMovementType.purchase,
        quantityDelta: 3,
      );

      final movements = await repo.listMovements(businessAId, productId: product['id'] as String);
      expect(movements, hasLength(1));
      expect(movements.first.quantity, 3);
      expect(movements.first.movementType, InventoryMovementType.purchase);

      // cross-tenant: a business_id the caller has no membership in at all
      // returns empty, not another business's data or an error.
      final crossTenant = await client.from('inventory_movements').select('id').eq('business_id', _uuid.v4());
      expect(crossTenant, isEmpty);

      await client.auth.signOut();
    });

    test('suppliers: MANAGER+ can create; a CASHIER-rank member cannot', () async {
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

      final repo = InventoryRepository(client);
      final created = await repo.createSupplier(
        Supplier(id: '', businessId: businessAId, name: 'Regression Supplier ${_uuid.v4()}', active: true),
      );
      final list = await repo.listSuppliers(businessAId);
      expect(list.map((s) => s.id), contains(created.id));
      await client.auth.signOut();

      // User A is a real CASHIER of Business B (Day 3 fixture) -- below the
      // MANAGER floor suppliers_insert requires.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        client.from('suppliers').insert({'business_id': businessBId, 'name': 'Should Be Rejected'}),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );
      await client.auth.signOut();
    });
  });

  group('Expenses', () {
    test('ADMIN+ can create an expense category and an expense against it', () async {
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
      final userAId = client.auth.currentUser!.id;

      final repo = ExpenseRepository(client);
      final category = await repo.createCategory(businessAId, 'Regression Category ${_uuid.v4()}');

      final created = await repo.create(
        Expense(
          id: '',
          businessId: businessAId,
          categoryId: category.id,
          amount: Decimal.parse('55000'),
          paymentMethod: PaymentMethod.cash,
          description: 'Regression expense',
          expenseDate: DateTime.now(),
          createdAt: DateTime.now(),
        ),
        createdBy: userAId,
      );

      expect(created.categoryName, category.name);
      expect(created.amount, Decimal.parse('55000'));

      final list = await repo.listForBusiness(businessAId, categoryId: category.id);
      expect(list.map((e) => e.id), contains(created.id));

      await repo.delete(created.id);
      final afterDelete = await client.from('expenses').select('id').eq('id', created.id);
      expect(afterDelete, isEmpty);

      await client.auth.signOut();
    });

    test('a member below ADMIN rank cannot create an expense', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // User A is a real CASHIER of Business B (Day 3 fixture) -- below the
      // ADMIN floor expenses_insert requires.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final userAId = (await client
              .from('business_members')
              .select('user_id')
              .eq('business_id', businessBId)
              .eq('role', 'CASHIER'))
          .first['user_id'] as String;
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      expect(client.auth.currentUser!.id, userAId, reason: 'sanity check: signed-in user must be the CASHIER fixture');

      await expectLater(
        client.from('expenses').insert({
          'business_id': businessBId,
          'amount': '10000',
          'created_by': userAId,
        }),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );

      await client.auth.signOut();
    });

    test('cross-tenant: a business_id the caller has no membership in returns no expenses', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);

      final crossTenant = await client.from('expenses').select('id').eq('business_id', _uuid.v4());
      expect(crossTenant, isEmpty);

      await client.auth.signOut();
    });
  });
}
