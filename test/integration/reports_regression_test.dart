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
}
