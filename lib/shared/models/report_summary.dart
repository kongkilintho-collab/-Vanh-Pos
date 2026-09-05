import 'package:decimal/decimal.dart';

/// Aggregated business metrics for a date range, computed client-side from
/// rows already returned under the pre-existing `is_member(business_id)`
/// SELECT policies on `sales`, `sale_items`, `commissions`, `expenses`, and
/// `sale_item_batch_allocations` (see ReportsRepository). Nothing here is
/// written back to the database -- this is a read-only report, not a new
/// financial ledger.
///
/// `cogs` (Phase 8 / 0055) is historically exact for any sale_item that has
/// a recorded cost snapshot at sale time:
/// - batch-tracked lines: `sale_item_batch_allocations.unit_cost_snapshot`
///   (immutable, recorded per batch consumed, since 0053/0054).
/// - unbatched lines sold from 0055 onward:
///   `sale_items.unit_cost_snapshot` (immutable, recorded once at sale
///   time).
/// - unbatched lines sold *before* 0055 existed: no historical cost was
///   ever captured, so these fall back to the product's *current*
///   `cost_price` -- still an *estimate* for exactly these legacy rows,
///   and only these. A cost_price change after the fact can still shift
///   `profit` for past ranges, but only insofar as they contain such
///   pre-0055 unbatched sales.
class ReportSummary {
  final Decimal revenue;
  final Decimal cogs;
  final Decimal commissionTotal;
  final Decimal expenseTotal;
  final int salesCount;

  const ReportSummary({
    required this.revenue,
    required this.cogs,
    required this.commissionTotal,
    required this.expenseTotal,
    required this.salesCount,
  });

  static final zero = ReportSummary(
    revenue: Decimal.zero,
    cogs: Decimal.zero,
    commissionTotal: Decimal.zero,
    expenseTotal: Decimal.zero,
    salesCount: 0,
  );

  Decimal get profit => revenue - cogs - commissionTotal - expenseTotal;
}

/// One day's revenue, for the Reports chart.
class DailyRevenue {
  final DateTime date;
  final Decimal revenue;

  const DailyRevenue({required this.date, required this.revenue});
}
