import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/report_summary.dart';

/// Read-only business reporting (Day 5). Every query here is a plain
/// SELECT against tables that have carried `is_member(business_id)` RLS
/// since the Day 1 foundation migrations (`sales`, `sale_items`,
/// `commissions`, `expenses`, `products`) -- no new RLS policy and no RPC
/// were needed, since nothing here writes anything or requires cross-table
/// atomicity. Deliberately independent from PosRepository/
/// CommissionRepository/ExpenseRepository (same query technique, not a
/// shared class) so nothing here can affect their write paths.
class ReportsRepository {
  final SupabaseClient _client;

  ReportsRepository(this._client);

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  /// `sales`/`sale_items`/`commissions.created_at` are `timestamptz` --
  /// comparing against a naive local-time string would be silently
  /// misinterpreted as UTC by Postgres (an hours-wide skew for any
  /// non-UTC caller), so every instant comparison converts to UTC first.
  String _instant(DateTime d) => d.toUtc().toIso8601String();

  Future<ReportSummary> summaryForRange(String businessId, DateTime from, DateTime to) async {
    final fromIso = _instant(from);
    final toIso = _instant(to);

    final salesRows = await _client
        .from('sales')
        .select('total_amount')
        .eq('business_id', businessId)
        .eq('status', 'COMPLETED')
        .gte('created_at', fromIso)
        .lte('created_at', toIso);
    var revenue = Decimal.zero;
    for (final row in salesRows as List) {
      revenue += Decimal.parse((row as Map<String, dynamic>)['total_amount'].toString());
    }

    final productItemRows = await _client
        .from('sale_items')
        .select('quantity, products(cost_price)')
        .eq('business_id', businessId)
        .eq('item_type', 'PRODUCT')
        .gte('created_at', fromIso)
        .lte('created_at', toIso);
    var cogs = Decimal.zero;
    for (final row in productItemRows as List) {
      final map = row as Map<String, dynamic>;
      final product = map['products'] as Map<String, dynamic>?;
      final costPrice = Decimal.parse((product?['cost_price'] ?? 0).toString());
      final quantity = map['quantity'] as int;
      cogs += costPrice * Decimal.fromInt(quantity);
    }

    final commissionRows = await _client
        .from('commissions')
        .select('commission_amount')
        .eq('business_id', businessId)
        .neq('status', 'REVERSED')
        .gte('created_at', fromIso)
        .lte('created_at', toIso);
    var commissionTotal = Decimal.zero;
    for (final row in commissionRows as List) {
      commissionTotal += Decimal.parse((row as Map<String, dynamic>)['commission_amount'].toString());
    }

    final expenseRows = await _client
        .from('expenses')
        .select('amount')
        .eq('business_id', businessId)
        .gte('expense_date', _dateOnly(from))
        .lte('expense_date', _dateOnly(to));
    var expenseTotal = Decimal.zero;
    for (final row in expenseRows as List) {
      expenseTotal += Decimal.parse((row as Map<String, dynamic>)['amount'].toString());
    }

    return ReportSummary(
      revenue: revenue,
      cogs: cogs,
      commissionTotal: commissionTotal,
      expenseTotal: expenseTotal,
      salesCount: (salesRows).length,
    );
  }

  /// One revenue total per calendar day in range, for the Reports chart.
  /// Grouped client-side -- the row volume a single business/date-range
  /// produces here doesn't justify a database-side aggregate view.
  Future<List<DailyRevenue>> dailyRevenue(String businessId, DateTime from, DateTime to) async {
    final rows = await _client
        .from('sales')
        .select('total_amount, created_at')
        .eq('business_id', businessId)
        .eq('status', 'COMPLETED')
        .gte('created_at', _instant(from))
        .lte('created_at', _instant(to))
        .order('created_at');

    final totalsByDay = <DateTime, Decimal>{};
    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      final createdAt = DateTime.parse(map['created_at'] as String).toLocal();
      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final amount = Decimal.parse(map['total_amount'].toString());
      totalsByDay[day] = (totalsByDay[day] ?? Decimal.zero) + amount;
    }

    final days = totalsByDay.keys.toList()..sort();
    return [for (final day in days) DailyRevenue(date: day, revenue: totalsByDay[day]!)];
  }

  /// Raw completed sales in range, for the Reports table/export.
  Future<List<Map<String, dynamic>>> salesForRange(String businessId, DateTime from, DateTime to) async {
    final rows = await _client
        .from('sales')
        .select('receipt_number, total_amount, payment_status, created_at')
        .eq('business_id', businessId)
        .eq('status', 'COMPLETED')
        .gte('created_at', _instant(from))
        .lte('created_at', _instant(to))
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
