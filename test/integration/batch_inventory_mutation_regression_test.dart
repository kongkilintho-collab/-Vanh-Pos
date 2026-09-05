// Live regression coverage for Phase 7 / 0053: the batch-aware adjust_stock
// signature (see supabase/migrations/0053_batch_inventory_mutation_primitives.sql)
// and the sale_item_batch_allocations table it introduces.
//
// Scope is deliberately narrow, mirroring the migration itself: the flat
// (unbatched) adjust_stock path is only spot-checked here for regression
// (its full behavior is already covered by inventory_expenses_regression_test.dart),
// while the batch-aware path and its validation matrix get full coverage.
// Nothing here calls complete_sale/void_sale or writes to
// sale_item_batch_allocations -- this migration adds no RPC that does.
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/batch_inventory_mutation_regression_test.dart
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
    '0053_batch_inventory_mutation_primitives.sql applied and seeded with '
    'the QA fixture accounts.';

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
/// record_opening_balance_batch, returning (productId, batchId). Mirrors the
/// P1 (0052) live-verification's own opening-balance sequence.
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
        'name': 'Batch Test Product ${_uuid.v4()}',
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
    'p_batch_number': 'REGRESSION-${_uuid.v4()}',
    'p_expiry_date': null,
  });
  final batchId = (batch as Map<String, dynamic>)['id'] as String;
  return (productId, batchId);
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  group('sale_item_batch_allocations schema', () {
    test('is readable (empty) by a member and writes are rejected for every role', () async {
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

      // SELECT is allowed for a member -- no rows expected yet since no RPC
      // in this migration ever inserts one.
      final selectResult = await client
          .from('sale_item_batch_allocations')
          .select('id')
          .eq('business_id', businessAId);
      expect(selectResult, isA<List>());

      // No INSERT policy exists at all -- expect PostgREST/RLS to reject
      // this even for the OWNER of the business.
      await expectLater(
        client.from('sale_item_batch_allocations').insert({
          'business_id': businessAId,
          'sale_item_id': _uuid.v4(),
          'quantity': 1,
          'unit_cost_snapshot': 1,
        }),
        throwsA(isA<PostgrestException>()),
      );

      await client.auth.signOut();
    });

    test('cross-tenant: a business_id the caller has no membership in returns no allocations', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);

      final crossTenant =
          await client.from('sale_item_batch_allocations').select('id').eq('business_id', _uuid.v4());
      expect(crossTenant, isEmpty);

      await client.auth.signOut();
    });
  });

  group('adjust_stock: flat (unbatched) path regression', () {
    test('an unbatched product still restocks exactly as before, with no batch_id supplied', () async {
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
            'name': '0053 Flat Path Test Product ${_uuid.v4()}',
            'selling_price': 20000,
            'stock_quantity': 5,
          })
          .select()
          .single();
      final productId = product['id'] as String;

      // Deliberately omits p_batch_id entirely -- the same call shape the
      // existing InventoryRepository.adjustStock makes -- to prove the new
      // trailing DEFAULT NULL parameter does not break existing callers.
      await client.rpc('adjust_stock', params: {
        'p_business_id': businessAId,
        'p_product_id': productId,
        'p_branch_id': null,
        'p_movement_type': 'PURCHASE',
        'p_quantity_delta': 10,
        'p_note': 'flat path regression',
      });

      final after = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(after['stock_quantity'], 15);

      await client.auth.signOut();
    });
  });

  group('adjust_stock: batch_tracked / p_batch_id pairing', () {
    test('a batch-tracked product without p_batch_id is rejected', () async {
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

      final (productId, _) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 10,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productId,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 1,
          'p_note': null,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('batch-tracked; a batch must be specified'))),
      );

      await client.auth.signOut();
    });

    test('an unbatched product with a p_batch_id supplied is rejected', () async {
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

      final (_, someBatchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 10,
        unitCost: 5,
      );
      final unbatchedProduct = await client
          .from('products')
          .insert({
            'business_id': businessAId,
            'name': '0053 Unbatched Guard Test Product ${_uuid.v4()}',
            'selling_price': 20000,
            'stock_quantity': 5,
          })
          .select()
          .single();

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': unbatchedProduct['id'] as String,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 1,
          'p_note': null,
          'p_batch_id': someBatchId,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('not batch-tracked; do not supply a batch'))),
      );

      await client.auth.signOut();
    });
  });

  group('adjust_stock: batch-aware happy path and invariants', () {
    test('a batch-aware PURCHASE increases stock_quantity and batch remaining_quantity together, '
        'and records a matching movement row', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 10,
        unitCost: 5,
      );

      await client.rpc('adjust_stock', params: {
        'p_business_id': businessAId,
        'p_product_id': productId,
        'p_branch_id': null,
        'p_movement_type': 'PURCHASE',
        'p_quantity_delta': 4,
        'p_note': 'batch-aware regression',
        'p_batch_id': batchId,
      });

      final productAfter =
          await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 14, reason: 'product stock cache must reflect +4');

      final batchAfter = await client
          .from('product_batches')
          .select('remaining_quantity, received_quantity')
          .eq('id', batchId)
          .single();
      expect(batchAfter['remaining_quantity'], 14, reason: 'batch remaining must move in lockstep with product stock');
      expect(batchAfter['received_quantity'], 10, reason: 'received_quantity is a permanent receipt fact, never altered by adjust_stock');

      final movements = await client
          .from('inventory_movements')
          .select()
          .eq('product_id', productId)
          .eq('reference_type', 'manual_adjustment')
          .eq('movement_type', 'PURCHASE');
      expect(movements, hasLength(1));
      final movement = (movements as List).first as Map<String, dynamic>;
      expect(movement['quantity'], 4);
      expect(movement['batch_id'], batchId);
      expect(movement['reference_id'], isNull);

      await client.auth.signOut();
    });

    test('a batch-aware OUT adjustment reaching exactly zero remaining_quantity is accepted', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 6,
        unitCost: 5,
      );

      await client.rpc('adjust_stock', params: {
        'p_business_id': businessAId,
        'p_product_id': productId,
        'p_branch_id': null,
        'p_movement_type': 'DAMAGE',
        'p_quantity_delta': -6,
        'p_note': 'deplete to exactly zero',
        'p_batch_id': batchId,
      });

      final batchAfter =
          await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 0);

      final productAfter =
          await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 0);

      await client.auth.signOut();
    });

    test('an IN adjustment that would exceed the batch\'s received_quantity is rejected, state unchanged', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 5,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productId,
          'p_branch_id': null,
          'p_movement_type': 'RETURN',
          'p_quantity_delta': 1,
          'p_note': null,
          'p_batch_id': batchId,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('exceed the batch\'s received quantity'))),
      );

      final productAfter =
          await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 5, reason: 'rejected adjustment must leave stock unchanged');
      final batchAfter =
          await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 5, reason: 'rejected adjustment must leave the batch unchanged');

      await client.auth.signOut();
    });

    test('an OUT adjustment that would take remaining_quantity below zero is rejected, state unchanged', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 3,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productId,
          'p_branch_id': null,
          'p_movement_type': 'DAMAGE',
          'p_quantity_delta': -4,
          'p_note': null,
          'p_batch_id': batchId,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('below zero remaining quantity'))),
      );

      final productAfter =
          await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 3);
      final batchAfter =
          await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 3);

      await client.auth.signOut();
    });

    test('a zero delta is rejected on the batch-aware path exactly as on the flat path', () async {
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

      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 5,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productId,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 0,
          'p_note': null,
          'p_batch_id': batchId,
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('must not be zero'))),
      );

      await client.auth.signOut();
    });
  });

  group('adjust_stock: product-level floor protection (0053 P1 fix)', () {
    test('an OUT adjustment the batch alone would allow is still rejected once a real sale has left '
        'product stock lower than the batch\'s (stale) remaining_quantity, with no partial mutation', () async {
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

      // Reproduces the exact scenario the P1 finding described: complete_sale
      // (unmodified, out of 0053's scope) decrements products.stock_quantity
      // for a batch-tracked product without ever touching
      // product_batches.remaining_quantity, so the batch is left stale-high
      // relative to the product's real stock the moment a normal POS sale
      // happens. This uses the existing, unmodified PosRepository.completeSale
      // -- the same call pos_checkout_regression_test.dart already exercises
      // -- purely to set up that state; nothing about complete_sale itself is
      // touched or asserted on here.
      final (productId, batchId) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 10,
        unitCost: 5,
      );

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final product = await client.from('products').select('name').eq('id', productId).single();
      await posRepo.completeSale(
        businessId: businessAId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'PRODUCT',
            'service_id': null,
            'product_id': productId,
            'staff_id': null,
            'name_snapshot': product['name'],
            'quantity': 7,
            'unit_price': '20000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '140000',
        idempotencyKey: _uuid.v4(),
      );

      // Sanity-check the setup actually produced the intended divergence:
      // stock_quantity=3 (10-7), remaining_quantity still 10 (untouched).
      final afterSale = await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(afterSale['stock_quantity'], 3, reason: 'setup sanity check: the sale must have decremented stock');
      final batchAfterSale =
          await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfterSale['remaining_quantity'], 10,
          reason: 'setup sanity check: complete_sale must leave the batch untouched, proving the stale state');

      // -8 against the batch alone would be fine (10-8=2 >= 0), but the
      // product only has 3 left (3-8=-5) -- the product-level floor guard
      // added for the P1 fix must reject this before any mutation occurs.
      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productId,
          'p_branch_id': null,
          'p_movement_type': 'DAMAGE',
          'p_quantity_delta': -8,
          'p_note': null,
          'p_batch_id': batchId,
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('below zero stock'))),
      );

      final productAfter =
          await client.from('products').select('stock_quantity').eq('id', productId).single();
      expect(productAfter['stock_quantity'], 3, reason: 'rejected adjustment must leave product stock unchanged');
      final batchAfter =
          await client.from('product_batches').select('remaining_quantity').eq('id', batchId).single();
      expect(batchAfter['remaining_quantity'], 10, reason: 'rejected adjustment must leave the batch unchanged');
      final movements = await client
          .from('inventory_movements')
          .select('id')
          .eq('product_id', productId)
          .eq('movement_type', 'DAMAGE');
      expect(movements, isEmpty, reason: 'no movement row should exist for a rejected adjustment');

      await client.auth.signOut();
    });
  });

  group('adjust_stock: batch tenant/product isolation', () {
    test('a batch belonging to a different product (same business) is rejected as not found', () async {
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

      final (_, batchForProductOne) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 5,
        unitCost: 5,
      );
      final (productTwoId, _) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 5,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productTwoId,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 1,
          'p_note': null,
          'p_batch_id': batchForProductOne,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('Batch not found for this product in this business'))),
      );

      await client.auth.signOut();
    });

    test('a batch belonging to another business cannot be used, even by a real MANAGER+ of the caller\'s own business', () async {
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
      final (_, batchInB) = await _createBatchTrackedProduct(
        client,
        businessBId,
        openingQuantity: 5,
        unitCost: 5,
      );
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final (productInA, _) = await _createBatchTrackedProduct(
        client,
        businessAId,
        openingQuantity: 5,
        unitCost: 5,
      );

      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessAId,
          'p_product_id': productInA,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 1,
          'p_note': null,
          'p_batch_id': batchInB,
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.message, 'message', contains('Batch not found for this product in this business'))),
      );

      await client.auth.signOut();
    });
  });

  group('adjust_stock: authorization (batch-aware path)', () {
    test('a CASHIER-rank member cannot make a batch-aware adjustment', () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;

      // Business B belongs to User B; User A is a real CASHIER there (Day 3
      // fixture), same technique inventory_expenses_regression_test.dart uses.
      await _signIn(client, _ownerBEmail, _ownerBPassword);
      final businessBId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final (productInB, batchInB) = await _createBatchTrackedProduct(
        client,
        businessBId,
        openingQuantity: 5,
        unitCost: 5,
      );
      await client.auth.signOut();

      await _signIn(client, _ownerAEmail, _ownerAPassword);
      await expectLater(
        client.rpc('adjust_stock', params: {
          'p_business_id': businessBId,
          'p_product_id': productInB,
          'p_branch_id': null,
          'p_movement_type': 'ADJUSTMENT',
          'p_quantity_delta': 1,
          'p_note': null,
          'p_batch_id': batchInB,
        }),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission'))),
      );

      await client.auth.signOut();
    });
  });
}
