import 'package:decimal/decimal.dart';

/// Aggregated business metrics for a date range, computed client-side from
/// rows already returned under the pre-existing `is_member(business_id)`
/// SELECT policies on `sales`, `sale_items`, `commissions`, and `expenses`
/// (see ReportsRepository). Nothing here is written back to the database --
/// this is a read-only report, not a new financial ledger.
///
/// `profit` is explicitly an *estimate*: `cogs` uses each product's
/// *current* `cost_price` (no historical cost is snapshotted anywhere in
/// the schema), so a price change after the fact will retroactively shift
/// the estimate for past ranges too.
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
