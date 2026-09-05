// Live regression coverage for Day 5: read-only business reporting
// (ReportsRepository -- see lib/features/reports/data/reports_repository.dart).
//
// Day 5 introduces no new table, RLS policy, or RPC -- every query here
// rides the same is_member(business_id) SELECT policies that sales,
// sale_items, commissions, and expenses have carried since the Day 1
// foundation migrations (0015_rls_policies.sql, unmodified). There is
// therefore no new write path, no new atomicity requirement, and no new
// idempotency behavior to test here -- Day 5 is pure aggregation over
// already-tested, already-authorized rows.
//
// Because this project's live Supabase data accumulates across every QA
// session (this file's fixtures are not the only rows ever inserted into
// Business A/B), the aggregation-correctness tests use a before/after
// delta over a narrow time window rather than an absolute sum: they read
// the summary for a window, insert a precisely-known fixture, read the
// summary again, and assert the *difference* matches the known fixture
// value exactly. This is robust to any concurrent or historical data in
// the same business and is a stronger test of the aggregation logic
// itself than an absolute-value assertion would be.
//
// Uses the same live Supabase project and QA fixture accounts as the
// other integration tests in this directory -- see
// business_repository_regression_test.dart's header for setup details and
// the skip-when-unconfigured behavior, which this file mirrors.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/reports_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/features/reports/data/reports_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

/// Creates an unbatched product then converts it via
/// record_opening_balance_batch, returning (productId, batchId). Mirrors
/// batch_aware_sales_regression_test.dart's own helper.
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
        'name': '0055 Batch Test Product ${_uuid.v4()}',
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
    'p_batch_number': '0055-REGRESSION-${_uuid.v4()}',
    'p_expiry_date': null,
  });
  final batchId = (batch as Map<String, dynamic>)['id'] as String;
  return (productId, batchId);
}

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project seeded with the '
    'QA fixture accounts.';

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

  test('revenue, COGS, commission, expenses, and profit are computed exactly for a known fixture', () async {
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

    final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
    final repo = ReportsRepository(client);
    final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
    final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);
    final beforeDaily = await repo.dailyRevenue(businessAId, windowStart, probeWindowEnd);

    // Known fixture: one service (price 200,000; 10% commission, attributed
    // to the OWNER as staff so a commission row is guaranteed) and one
    // product line (unit price 50,000 x 2; cost price 30,000), completed
    // as a single sale, plus one expense.
    final service = await client
        .from('services')
        .insert({'business_id': businessAId, 'name': 'Report Test Service ${_uuid.v4()}', 'price': 200000, 'commission_value': 10})
        .select()
        .single();
    final product = await client
        .from('products')
        .insert({'business_id': businessAId, 'name': 'Report Test Product ${_uuid.v4()}', 'cost_price': 30000, 'selling_price': 50000, 'stock_quantity': 10})
        .select()
        .single();

    final posRepo = PosRepository(client);
    final branchId = await posRepo.primaryBranchId(businessAId);
    await posRepo.completeSale(
      businessId: businessAId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': ownerAId,
          'name_snapshot': 'Report Test Service',
          'quantity': 1,
          'unit_price': '200000',
          'discount_amount': '0',
        },
        {
          'item_type': 'PRODUCT',
          'service_id': null,
          'product_id': product['id'],
          'staff_id': null,
          'name_snapshot': 'Report Test Product',
          'quantity': 2,
          'unit_price': '50000',
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '300000',
      idempotencyKey: _uuid.v4(),
    );

    await client.from('expenses').insert({
      'business_id': businessAId,
      'amount': '25000',
      'created_by': ownerAId,
    });

    final windowEnd = DateTime.now().add(const Duration(minutes: 5));
    final after = await repo.summaryForRange(businessAId, windowStart, windowEnd);

    expect(after.revenue - before.revenue, Decimal.parse('300000'), reason: 'revenue delta must equal the sale total');
    expect(after.cogs - before.cogs, Decimal.parse('60000'), reason: 'COGS delta must equal 2 x product cost_price (30,000)');
    expect(after.commissionTotal - before.commissionTotal, Decimal.parse('20000'), reason: 'commission delta must equal 10% of the service price');
    expect(after.expenseTotal - before.expenseTotal, Decimal.parse('25000'), reason: 'expense delta must equal the inserted expense');
    expect(after.salesCount - before.salesCount, 1);
    expect(
      after.profit - before.profit,
      Decimal.parse('195000'),
      reason: 'profit delta must equal 300,000 - 60,000 - 20,000 - 25,000',
    );

    // Daily breakdown groups the new sale under today, not lost or split.
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final afterDaily = await repo.dailyRevenue(businessAId, windowStart, windowEnd);
    final beforeTodayRevenue =
        beforeDaily.where((d) => d.date == todayKey).fold(Decimal.zero, (sum, d) => sum + d.revenue);
    final afterTodayRevenue =
        afterDaily.where((d) => d.date == todayKey).fold(Decimal.zero, (sum, d) => sum + d.revenue);
    expect(afterTodayRevenue - beforeTodayRevenue, Decimal.parse('300000'));

    // The sale itself is visible in the range's sales list. Compared as
    // Decimal, not a raw string -- Postgres's numeric JSON serialization
    // doesn't guarantee a fixed trailing-zero count.
    final sales = await repo.salesForRange(businessAId, windowStart, windowEnd);
    expect(
      sales.any((s) => Decimal.parse(s['total_amount'].toString()) == Decimal.parse('300000')),
      isTrue,
    );

    await client.auth.signOut();
  });

  test('an expense dated yesterday is excluded from a today-only range but included when the range covers it', () async {
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

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStart = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final yesterdayEnd = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59, 999);

    final repo = ReportsRepository(client);
    final beforeToday = await repo.summaryForRange(businessAId, todayStart, todayEnd);
    final beforeYesterday = await repo.summaryForRange(businessAId, yesterdayStart, yesterdayEnd);

    await client.from('expenses').insert({
      'business_id': businessAId,
      'amount': '17000',
      'expense_date': yesterdayStart.toIso8601String().split('T').first,
      'created_by': ownerAId,
    });

    final afterToday = await repo.summaryForRange(businessAId, todayStart, todayEnd);
    final afterYesterday = await repo.summaryForRange(businessAId, yesterdayStart, yesterdayEnd);

    expect(afterToday.expenseTotal - beforeToday.expenseTotal, Decimal.zero, reason: 'a yesterday-dated expense must not leak into a today-only range');
    expect(afterYesterday.expenseTotal - beforeYesterday.expenseTotal, Decimal.parse('17000'), reason: 'the same expense must be included when the range covers its date');

    await client.auth.signOut();
  });

  test('cross-tenant: a business_id the caller has no membership in yields an all-zero summary, not an error', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);

    final nonMemberBusinessId = _uuid.v4();
    final repo = ReportsRepository(client);
    final now = DateTime.now();
    final summary = await repo.summaryForRange(nonMemberBusinessId, now.subtract(const Duration(days: 1)), now);

    expect(summary.revenue, Decimal.zero);
    expect(summary.cogs, Decimal.zero);
    expect(summary.commissionTotal, Decimal.zero);
    expect(summary.expenseTotal, Decimal.zero);
    expect(summary.salesCount, 0);

    final daily = await repo.dailyRevenue(nonMemberBusinessId, now.subtract(const Duration(days: 1)), now);
    expect(daily, isEmpty);

    final sales = await repo.salesForRange(nonMemberBusinessId, now.subtract(const Duration(days: 1)), now);
    expect(sales, isEmpty);

    await client.auth.signOut();
  });

  test('an unauthenticated caller sees an all-zero summary for a real business, not an error', () async {
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
    await client.auth.signOut();

    final repo = ReportsRepository(client);
    final now = DateTime.now();
    final summary = await repo.summaryForRange(businessAId, now.subtract(const Duration(days: 1)), now);

    expect(summary.revenue, Decimal.zero, reason: 'RLS must block an anonymous caller from reading any sales rows');
    expect(summary.commissionTotal, Decimal.zero);
    expect(summary.expenseTotal, Decimal.zero);
  });

  // Phase 8 / 0055 — historical COGS correctness (F-1: voided sales no
  // longer counted; F-2: historical cost snapshots preferred over current
  // cost_price). "Test 1 — COMPLETED flat sale" from the frozen design's
  // test matrix is already the first test in this file (revenue/COGS/
  // profit for a known fixture) and "tenant isolation" is already the
  // cross-tenant test above -- neither is duplicated here.
  group('Phase 8 / 0055: historical COGS correctness', () {
    test('a VOIDED flat sale contributes zero revenue, zero COGS, and zero profit impact (F-1)', () async {
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

      final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
      final repo = ReportsRepository(client);

      final product = await client
          .from('products')
          .insert({'business_id': businessAId, 'name': '0055 Void Flat Product ${_uuid.v4()}', 'cost_price': 12000, 'selling_price': 25000, 'stock_quantity': 10})
          .select()
          .single();

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
      final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);

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
            'name_snapshot': '0055 Void Flat Product',
            'quantity': 3,
            'unit_price': '25000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '75000',
        idempotencyKey: _uuid.v4(),
      );

      final windowEnd = DateTime.now().add(const Duration(minutes: 5));
      final afterSale = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(afterSale.revenue - before.revenue, Decimal.parse('75000'), reason: 'sanity: the sale must be counted while COMPLETED');
      expect(afterSale.cogs - before.cogs, Decimal.parse('36000'), reason: 'sanity: 3 x cost_price 12,000 while COMPLETED');

      await posRepo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: '0055 F-1 regression void');

      final afterVoid = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(afterVoid.revenue - before.revenue, Decimal.zero, reason: 'a VOIDED sale must contribute zero revenue');
      expect(afterVoid.cogs - before.cogs, Decimal.zero, reason: 'a VOIDED sale must contribute zero COGS -- this is F-1');
      expect(afterVoid.profit - before.profit, Decimal.zero, reason: 'zero net profit impact once voided');

      await client.auth.signOut();
    });

    test('a legacy pre-0055 unbatched line with no cost snapshot falls back to current cost_price as a labeled estimate', () async {
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

      // Deliberately dynamic, not a fabricated fixture: 0055's own
      // complete_sale always populates unit_cost_snapshot now, so no new
      // row can ever be null. This proves the fallback path against real
      // pre-0055 history already in this project's live QA data, or skips
      // cleanly once none remains (e.g. against a fresh project).
      final legacyRows = await client
          .from('sale_items')
          .select('id, sale_id, quantity, products(cost_price), sales!inner(status, created_at)')
          .eq('business_id', businessAId)
          .eq('item_type', 'PRODUCT')
          .filter('unit_cost_snapshot', 'is', null)
          .eq('sales.status', 'COMPLETED');

      Map<String, dynamic>? isolated;
      for (final r in (legacyRows as List).cast<Map<String, dynamic>>()) {
        final siblingCount = await client.from('sale_items').select('id').eq('sale_id', r['sale_id'] as String).eq('item_type', 'PRODUCT');
        if ((siblingCount as List).length == 1) {
          isolated = r;
          break;
        }
      }

      if (isolated == null) {
        markTestSkipped(
          'no pre-0055 unbatched sale (single PRODUCT line, unit_cost_snapshot IS NULL) remains in this '
          'project\'s live history to verify the legacy fallback against -- expected on a fresh project.',
        );
        return;
      }

      final saleCreatedAt = DateTime.parse((isolated['sales'] as Map<String, dynamic>)['created_at'] as String);
      final quantity = isolated['quantity'] as int;
      final costPrice = Decimal.parse(((isolated['products'] as Map<String, dynamic>?)?['cost_price'] ?? 0).toString());

      final repo = ReportsRepository(client);
      final summary = await repo.summaryForRange(businessAId, saleCreatedAt, saleCreatedAt);
      expect(
        summary.cogs,
        costPrice * Decimal.fromInt(quantity),
        reason: 'a legacy line with no cost snapshot must use current products.cost_price as the documented estimate',
      );

      await client.auth.signOut();
    });

    test('a new unbatched sale snapshots cost at sale time; a later cost_price change does not retroactively change its COGS', () async {
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

      final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
      final repo = ReportsRepository(client);

      final product = await client
          .from('products')
          .insert({'business_id': businessAId, 'name': '0055 Snapshot Flat Product ${_uuid.v4()}', 'cost_price': 8000, 'selling_price': 20000, 'stock_quantity': 10})
          .select()
          .single();
      final productId = product['id'] as String;

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
      final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
      final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);

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
            'name_snapshot': '0055 Snapshot Flat Product',
            'quantity': 2,
            'unit_price': '20000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '40000',
        idempotencyKey: _uuid.v4(),
      );

      final saleItem = await client.from('sale_items').select('id, unit_cost_snapshot').eq('product_id', productId).single();
      expect(saleItem['unit_cost_snapshot'], isNotNull, reason: 'complete_sale must populate the snapshot for a new unbatched line');
      expect(num.parse(saleItem['unit_cost_snapshot'].toString()), 8000);

      // Change the product's cost after the sale -- via the sanctioned
      // MANAGER+ RPC, not a direct write.
      await client.rpc('set_product_cost', params: {
        'p_business_id': businessAId,
        'p_product_id': productId,
        'p_cost_price': 99000,
      });

      final windowEnd = DateTime.now().add(const Duration(minutes: 5));
      final after = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(
        after.cogs - before.cogs,
        Decimal.parse('16000'),
        reason: 'COGS must remain 2 x the snapshotted 8,000, not the new current cost_price of 99,000',
      );

      await client.auth.signOut();
    });

    test('single-batch COGS uses the allocation unit_cost_snapshot, not a diverged current product cost_price', () async {
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

      final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
      final repo = ReportsRepository(client);
      final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
      final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);

      final (productId, _) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 5000);

      final posRepo = PosRepository(client);
      final branchId = await posRepo.primaryBranchId(businessAId);
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
            'name_snapshot': '0055 Batch Test Product',
            'quantity': 4,
            'unit_price': '20000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '80000',
        idempotencyKey: _uuid.v4(),
      );

      // Diverge the product's current cost from the batch's immutable
      // snapshot -- the report must ignore this change entirely for this
      // already-allocated quantity.
      await client.rpc('set_product_cost', params: {
        'p_business_id': businessAId,
        'p_product_id': productId,
        'p_cost_price': 77777,
      });

      final windowEnd = DateTime.now().add(const Duration(minutes: 5));
      final after = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(
        after.cogs - before.cogs,
        Decimal.parse('20000'),
        reason: '4 x the batch unit_cost_snapshot (5,000), never the diverged current cost_price (77,777)',
      );

      await client.auth.signOut();
    });

    test('multi-batch COGS (documented, live-verification-only limitation)', () async {
      // Per the 0054 design freeze (Decision 8), no receiving RPC exists to
      // create a second batch on an already batch-tracked product through
      // the API -- the same constraint that made the 0054 multi-batch FEFO
      // test a documented live-verification-only case applies identically
      // here. The single-batch test above already proves the exact
      // mechanism this case would exercise (COGS = allocation.quantity x
      // allocation.unit_cost_snapshot, summed, never current cost_price);
      // multi-batch only adds a second addend to the same SUM, reviewed
      // directly in reports_repository.dart's own source.
      markTestSkipped(
        'requires a manually-seeded second product_batches row via the Supabase SQL Editor -- see the '
        '0054 design freeze, Decision 8. The single-batch test above proves the same summation mechanism.',
      );
    });

    test('voiding a batch-aware sale reverses its revenue and COGS contribution to zero, without touching allocations', () async {
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

      final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
      final repo = ReportsRepository(client);
      final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
      final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);

      final (productId, _) = await _createBatchTrackedProduct(client, businessAId, openingQuantity: 10, unitCost: 3000);
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
            'product_id': productId,
            'staff_id': null,
            'name_snapshot': '0055 Batch Void Product',
            'quantity': 5,
            'unit_price': '20000',
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '100000',
        idempotencyKey: _uuid.v4(),
      );

      final saleItem = await client.from('sale_items').select('id').eq('sale_id', sale['id']).single();
      final allocationBefore =
          await client.from('sale_item_batch_allocations').select('id, batch_id, quantity, unit_cost_snapshot').eq('sale_item_id', saleItem['id']).single();

      final windowEnd = DateTime.now().add(const Duration(minutes: 5));
      final afterSale = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(afterSale.cogs - before.cogs, Decimal.parse('15000'), reason: 'sanity: 5 x 3,000 while COMPLETED');

      await posRepo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: '0055 batch void regression');

      final afterVoid = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(afterVoid.revenue - before.revenue, Decimal.zero);
      expect(afterVoid.cogs - before.cogs, Decimal.zero, reason: 'batch-aware void must also zero out COGS');

      final allocationAfter =
          await client.from('sale_item_batch_allocations').select('id, batch_id, quantity, unit_cost_snapshot').eq('id', allocationBefore['id']).single();
      expect(allocationAfter, equals(allocationBefore), reason: 'the allocation row must remain byte-for-byte unchanged after void');

      await client.auth.signOut();
    });

    test('voiding a legacy flat sale reverses its revenue and COGS contribution to zero', () async {
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

      final windowStart = DateTime.now().subtract(const Duration(seconds: 5));
      final repo = ReportsRepository(client);
      final probeWindowEnd = DateTime.now().add(const Duration(minutes: 5));
      final before = await repo.summaryForRange(businessAId, windowStart, probeWindowEnd);

      final product = await client
          .from('products')
          .insert({'business_id': businessAId, 'name': '0055 Legacy Void Product ${_uuid.v4()}', 'cost_price': 4000, 'selling_price': 10000, 'stock_quantity': 10})
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
            'name_snapshot': '0055 Legacy Void Product',
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

      await posRepo.voidSale(businessId: businessAId, saleId: sale['id'] as String, reason: '0055 legacy void regression');

      final windowEnd = DateTime.now().add(const Duration(minutes: 5));
      final after = await repo.summaryForRange(businessAId, windowStart, windowEnd);
      expect(after.revenue - before.revenue, Decimal.zero);
      expect(after.cogs - before.cogs, Decimal.zero);

      await client.auth.signOut();
    });
  });
}
