import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/report_summary.dart';

/// Read-only business reporting (Day 5). Every query here is a plain
/// SELECT against tables that have carried `is_member(business_id)` RLS
/// since the Day 1 foundation migrations (`sales`, `sale_items`,
/// `commissions`, `expenses`, `products`, and -- since Phase 8 --
/// `sale_item_batch_allocations`) -- no new RLS policy and no RPC were
/// needed, since nothing here writes anything or requires cross-table
/// atomicity. Deliberately independent from PosRepository/
/// CommissionRepository/ExpenseRepository (same query technique, not a
/// shared class) so nothing here can affect their write paths.
///
/// COGS (Phase 8 / 0055) is scoped to the same COMPLETED-sale set as
/// revenue and sourced per line from whichever historical snapshot
/// exists -- batch allocation snapshots, then the sale item's own cost
/// snapshot, then (only for sale_items predating 0055) the product's
/// current cost_price as a labeled estimate. See `summaryForRange` for
/// the exact precedence.
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
        .select('id, total_amount')
        .eq('business_id', businessId)
        .eq('status', 'COMPLETED')
        .gte('created_at', fromIso)
        .lte('created_at', toIso);
    var revenue = Decimal.zero;
    final completedSaleIds = <String>[];
    for (final row in salesRows as List) {
      final map = row as Map<String, dynamic>;
      revenue += Decimal.parse(map['total_amount'].toString());
      completedSaleIds.add(map['id'] as String);
    }

    // COGS is scoped to the exact same COMPLETED-sale set as revenue above
    // (by reusing completedSaleIds, not a separate date/status filter on
    // sale_items) -- this is what makes a VOIDED sale's product cost
    // excluded from COGS just as its revenue already was.
    //
    // Historical cost precedence per line, never recomputed from current
    // state: (1) persisted batch allocations
    // (sale_item_batch_allocations.unit_cost_snapshot -- immutable, set by
    // complete_sale at sale time, 0053/0054) when the line was
    // batch-tracked at sale time; else (2) sale_items.unit_cost_snapshot
    // (immutable, set by complete_sale at sale time, added for unbatched
    // lines from this point forward); else (3) the product's *current*
    // cost_price, for sale_items created before that snapshot existed --
    // an explicitly-labeled estimate only, never claimed as historical.
    var cogs = Decimal.zero;
    if (completedSaleIds.isNotEmpty) {
      final productItemRows = await _client
          .from('sale_items')
          .select(
            'quantity, unit_cost_snapshot, products(cost_price), sale_item_batch_allocations(quantity, unit_cost_snapshot)',
          )
          .eq('business_id', businessId)
          .eq('item_type', 'PRODUCT')
          .inFilter('sale_id', completedSaleIds);
      for (final row in productItemRows as List) {
        final map = row as Map<String, dynamic>;
        final allocations = (map['sale_item_batch_allocations'] as List?) ?? const [];
        if (allocations.isNotEmpty) {
          for (final allocation in allocations) {
            final a = allocation as Map<String, dynamic>;
            final allocatedQuantity = Decimal.parse(a['quantity'].toString());
            final allocationCost = Decimal.parse(a['unit_cost_snapshot'].toString());
            cogs += allocatedQuantity * allocationCost;
          }
        } else if (map['unit_cost_snapshot'] != null) {
          final snapshotCost = Decimal.parse(map['unit_cost_snapshot'].toString());
          final quantity = map['quantity'] as int;
          cogs += snapshotCost * Decimal.fromInt(quantity);
        } else {
          final product = map['products'] as Map<String, dynamic>?;
          final costPrice = Decimal.parse((product?['cost_price'] ?? 0).toString());
          final quantity = map['quantity'] as int;
          cogs += costPrice * Decimal.fromInt(quantity);
        }
      }
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
