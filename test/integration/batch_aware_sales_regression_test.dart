// Live regression coverage for Phase 7 / 0054: batch-aware complete_sale
// (FEFO allocation, per-batch inventory movements, immutable COGS
// snapshots) and batch-aware void_sale restoration (see
// supabase/migrations/0054_batch_aware_sales.sql).
//
// Scope mirrors the migration itself: the flat (unbatched) complete_sale/
// void_sale paths are only spot-checked here for regression (full coverage
// already exists in pos_checkout_regression_test.dart and
// void_sale_regression_test.dart), while the batch-aware paths and their
// invariants get full coverage. Nothing here touches FEFO's multi-batch
// ordering with real live data -- per the 0054 design freeze, no receiving
// RPC exists to create a second batch on an already-converted product
// through the API, so that specific case is a documented, skipped
// placeholder pointing at the manual live-verification setup instead of
// unsafe/invented test scaffolding.
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/batch_aware_sales_regression_test.dart
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
    '0054_batch_aware_sales.sql applied and seeded with the QA fixture '
    'accounts.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

/// Creates an unbatched product then converts it via
/// record_opening_balance_batch, returning (productId, batchId).
Future<(String, String)> _createBatchTrackedProduct(
  SupabaseClient client,
  String businessId, {
  required int openingQuantity,
  required num unitCost,
}) async {
  final product = await client
      .from('products')
      .insert({
        'business_id': businessId,
        'name': '0054 Batch Test Product ${_uuid.v4()}',
        'selling_price': 20000,
        'cost_price': unitCost,
        'stock_quantity': openingQuantity,
      })
      .select()
      .single();
  final productId = product['id'] as String;

  final batch = await client.rpc('record_opening_balance_batch', params: {
    'p_business_id': businessId,
    'p_product_id': productId,
    'p_unit_cost': unitCost,
    'p_batch_number': '0054-REGRESSION-${_uuid.v4()}',
    'p_expiry_date': null,
  });
  final batchId = (batch as Map<String, dynamic>)['id'] as String;
  return (productId, batchId);
}

Future<Map<String, dynamic>> _sellProduct(
  PosRepository repo, {
  required String businessId,
  String? branchId,
  required String productId,
  required String name,
  required int quantity,
  required String unitPrice,
}) {
  final total = (int.parse(unitPrice) * quantity).toString();
  return repo.completeSale(
    businessId: businessId,
    branchId: branchId,
    customerId: null,
    items: [
      {
        'item_type': 'PRODUCT',
        'service_id': null,
        'product_id': productId,
        'staff_id': null,
        'name_snapshot': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount_amount': '0',
      },
    ],
    discountAmount: '0',
    taxAmount: '0',
    paymentMethod: 'CASH',
    paidAmount: total,
    idempotencyKey: _uuid.v4(),
  );
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  group('complete_sale: flat product regression (unaffected by 0054)', () {
    test('an unbatched product sale is unchanged: one SALE movement, batch_id null, no allocation row', () async {
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
          .insert({'business_id': businessAId, 'name': '0054 Flat Product ${_uuid.v4()}', 'selling_price': 15000, 'stock_quantity': 10})
          .select()
          .single();
      final productId = product['id'] as String;

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final sale = await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: product['name'] as String, quantity: 3, unitPrice: '15000');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 7);

      final movements = await client
          .from('inventory_movements')
          .select('quantity, batch_id, reference_type, reference_id')
          .eq('reference_type', 'sale')
          .eq('reference_id', sale['id']);
      expect(movements, hasLength(1));
      expect((movements as List).first['batch_id'], isNull);
      expect(movements.first['quantity'], -3);

      final saleItem = await client.from('sale_items').select('id').eq('sale_id', sale['id']).single();
      final allocations =
          await client.from('sale_item_batch_allocations').select('id').eq('sale_item_id', saleItem['id']);
      expect(allocations, isEmpty);

      await client.auth.signOut();
    });
  });

  group('complete_sale: batch-aware allocation (single batch)', () {
    test('a partial single-batch sale creates a matching allocation row, per-batch movement, and immutable cost snapshot', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 4000);

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final sale = await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 6, unitPrice: '20000');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 4, reason: '10 - 6');

      final batchAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 4, reason: 'must move in lockstep with product stock');

      final saleItem = await client.from('sale_items').select('id, quantity').eq('sale_id', sale['id']).single();

      final allocations = await client
          .from('sale_item_batch_allocations')
          .select('batch_id, quantity, unit_cost_snapshot')
          .eq('sale_item_id', saleItem['id']);
      expect(allocations, hasLength(1));
      final allocation = (allocations as List).first as Map<String, dynamic>;
      expect(allocation['batch_id'], batchId);
      expect(allocation['quantity'], 6);
      expect(num.parse(allocation['unit_cost_snapshot'].toString()), 4000);

      // Allocation-sum invariant: SUM(allocation.quantity) = sale_items.quantity.
      final totalAllocated = (allocations).fold<num>(0, (sum, a) => sum + (a['quantity'] as num));
      expect(totalAllocated, saleItem['quantity']);

      final movements = await client
          .from('inventory_movements')
          .select('quantity, batch_id')
          .eq('reference_type', 'sale')
          .eq('reference_id', sale['id']);
      expect(movements, hasLength(1));
      expect((movements as List).first['batch_id'], batchId);
      expect(movements.first['quantity'], -6);

      await client.auth.signOut();
    });

    test('a sale that exactly depletes the batch leaves remaining_quantity at zero', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 5, unitCost: 1000);

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 5, unitPrice: '20000');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 0);
      final batchAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 0);

      await client.auth.signOut();
    });
  });

  group('complete_sale: insufficient stock / atomicity', () {
    test('insufficient aggregate batch stock is rejected before any mutation -- no sale, item, allocation, or movement', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 3, unitCost: 1000);

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final idempotencyKey = _uuid.v4();

      await expectLater(
        repo.completeSale(
          businessId: businessAId,
          branchId: branchId,
          customerId: null,
          items: [
            {
              'item_type': 'PRODUCT',
              'service_id': null,
              'product_id': productId,
              'staff_id': null,
              'name_snapshot': '0054 Batch Test Product',
              'quantity': 4,
              'unit_price': '20000',
              'discount_amount': '0',
            },
          ],
          discountAmount: '0',
          taxAmount: '0',
          paymentMethod: 'CASH',
          paidAmount: '80000',
          idempotencyKey: idempotencyKey,
        ),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient stock for'))),
      );

      final noSale = await client.from('sales').select('id').eq('idempotency_key', idempotencyKey);
      expect(noSale, isEmpty, reason: 'no sale row must exist for a rejected checkout');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 3, reason: 'unchanged');
      final batchAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 3, reason: 'unchanged');

      final movements = await client.from('inventory_movements').select('id').eq('product_id', productId);
      expect(movements, isEmpty);

      await client.auth.signOut();
    });
  });

  group('complete_sale: multi-batch FEFO ordering', () {
    test('FEFO consumes the earliest-expiring eligible batch first, across multiple batches (LIVE-VERIFICATION ONLY)', () async {
      // Per the 0054 design freeze (Decision 8), no receiving RPC exists to
      // create a second batch on an already batch-tracked product through
      // the API -- adding one merely to make this test automatable would be
      // unrelated production scope creep. Multi-batch/FEFO-ordering
      // correctness is verified during live verification by manually
      // inserting a second product_batches row (a different expiry_date)
      // for a dedicated test product directly via the Supabase SQL Editor,
      // then confirming through this same test file's single-batch
      // assertions pattern that the earlier-expiring batch is drawn down
      // first. This is a documented limitation, not an untested code path:
      // the FEFO query itself (order by expiry_date asc nulls last,
      // received_at asc, id asc) is reviewed in the 0054 forensic review.
      markTestSkipped(
        'requires a manually-seeded second product_batches row (distinct expiry_date) via the '
        'Supabase SQL Editor -- see the 0054 design freeze, Decision 8. Not automatable through '
        'any currently-live RPC without introducing an out-of-scope receiving primitive.',
      );
    });
  });

  group('complete_sale: cross-product batch isolation', () {
    test('selling one batch-tracked product never touches a different batch-tracked product\'s batch', () async {
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

      final (productA, batchA) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 1000);
      final (_, batchB) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 1000);

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productA, name: '0054 Batch Test Product', quantity: 4, unitPrice: '20000');

      final batchAAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchA).single();
      expect(batchAAfter['remaining_quantity'], 6);
      final batchBAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchB).single();
      expect(batchBAfter['remaining_quantity'], 10, reason: 'a different product\'s batch must be completely untouched');

      await client.auth.signOut();
    });
  });

  group('void_sale: legacy and batch-aware restoration', () {
    test('voiding a legacy (unbatched) sale restores stock via one aggregate RETURN movement, batch_id null', () async {
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
          .insert({'business_id': businessAId, 'name': '0054 Void Legacy Product ${_uuid.v4()}', 'selling_price': 15000, 'stock_quantity': 10})
          .select()
          .single();
      final productId = product['id'] as String;

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final sale = await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: product['name'] as String, quantity: 4, unitPrice: '15000');

      await repo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: '0054 regression void');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 10, reason: 'fully restored');

      final returns = await client
          .from('inventory_movements')
          .select('quantity, batch_id')
          .eq('reference_type', 'sale_void')
          .eq('reference_id', sale['id']);
      expect(returns, hasLength(1));
      expect((returns as List).first['batch_id'], isNull);
      expect(returns.first['quantity'], 4);

      await client.auth.signOut();
    });

    test('voiding a batch-aware sale restores the exact batch and product stock, and leaves the allocation row unchanged', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 2500);

      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final sale = await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 6, unitPrice: '20000');

      final saleItem = await client.from('sale_items').select('id').eq('sale_id', sale['id']).single();
      final allocationBefore = await client
          .from('sale_item_batch_allocations')
          .select('id, batch_id, quantity, unit_cost_snapshot')
          .eq('sale_item_id', saleItem['id'])
          .single();

      await repo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: '0054 batch-aware void regression');

      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 10, reason: 'fully restored (4 remaining + 6 restored)');
      final batchAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 10, reason: 'fully restored');

      final returns = await client
          .from('inventory_movements')
          .select('quantity, batch_id')
          .eq('reference_type', 'sale_void')
          .eq('reference_id', sale['id']);
      expect(returns, hasLength(1));
      expect((returns as List).first['batch_id'], batchId);
      expect(returns.first['quantity'], 6);

      // Immutability: the original allocation row is untouched by the void.
      final allocationAfter = await client
          .from('sale_item_batch_allocations')
          .select('id, batch_id, quantity, unit_cost_snapshot')
          .eq('id', allocationBefore['id'])
          .single();
      expect(allocationAfter, equals(allocationBefore));

      await client.auth.signOut();
    });

    test('a second void attempt on an already-voided sale is rejected', () async {
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

      final (productId, _) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 5, unitCost: 1000);
      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);
      final sale = await _sellProduct(repo,
          businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 2, unitPrice: '20000');

      await repo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: 'first void');

      await expectLater(
        repo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: 'second void attempt'),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only a completed sale can be voided'))),
      );

      await client.auth.signOut();
    });
  });

  group('complete_sale / void_sale: authorization', () {
    test('a CASHIER-rank member can complete a batch-tracked sale', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // User A is a real CASHIER of Business B (Day 3 fixture) -- CASHIER
      // is complete_sale's own floor, so this must succeed.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final (productId, _) = await _createBatchTrackedProduct(client, businessBId, openingQuantity: 5, unitCost: 1000);
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessBId);
      final sale = await _sellProduct(repo,
          businessId: businessBId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 2, unitPrice: '20000');
      expect(sale['status'], 'COMPLETED');

      await client.auth.signOut();
    });

    test('a CASHIER-rank member cannot void a sale (MANAGER floor enforced, unchanged)', () async {
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
      final (productId, _) = await _createBatchTrackedProduct(client, businessBId, openingQuantity: 5, unitCost: 1000);
      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessBId);
      final sale = await _sellProduct(repo,
          businessId: businessBId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 1, unitPrice: '20000');
      await client.auth.signOut();

      // User A is a real CASHIER of Business B -- below the MANAGER floor
      // void_sale requires.
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        repo.voidSale(businessId: businessBId, saleId: sale['id'] as String, reason: 'should be rejected'),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
      );

      await client.auth.signOut();
    });
  });

  group('complete_sale: concurrency', () {
    test('two concurrent sales competing for the same batch serialize correctly -- no oversell, no negative remainder', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 1000);
      final repo = PosRepository(client);
      final branchId = await repo.primaryBranchId(businessAId);

      // Two sales of 6 each against a batch of 10 -- combined demand (12)
      // exceeds supply, so exactly one must succeed and the other must be
      // cleanly rejected; neither outcome may ever push remaining_quantity
      // below zero (proving the product-then-batch lock serializes them).
      final results = await Future.wait([
        _sellProduct(repo, businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 6, unitPrice: '20000')
            .then<Object?>((v) => v)
            .catchError((Object e) => e),
        _sellProduct(repo, businessId: businessAId, branchId: branchId, productId: productId, name: '0054 Batch Test Product', quantity: 6, unitPrice: '20000')
            .then<Object?>((v) => v)
            .catchError((Object e) => e),
      ]);

      final successes = results.whereType<Map<String, dynamic>>().toList();
      final failures = results.whereType<PostgrestException>().toList();
      expect(successes, hasLength(1), reason: 'exactly one of the two concurrent sales must succeed');
      expect(failures, hasLength(1), reason: 'the other must be cleanly rejected, not silently oversold');

      final batchAfter = await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 4, reason: '10 - 6, never negative, no lost update');
      final productAfter = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 4);

      await client.auth.signOut();
    });
  });
}
