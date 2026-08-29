import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/report_summary.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/widgets/date_range_filter.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

final reportDateRangeProvider =
    StateProvider.autoDispose<DateRangeSelection>((ref) => DateRangeSelection.today());

final reportSummaryProvider = FutureProvider.autoDispose<ReportSummary>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return ReportSummary.zero;
  final range = ref.watch(reportDateRangeProvider);
  return ref.watch(reportsRepositoryProvider).summaryForRange(membership.business.id, range.from, range.to);
});

final dailyRevenueProvider = FutureProvider.autoDispose<List<DailyRevenue>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final range = ref.watch(reportDateRangeProvider);
  return ref.watch(reportsRepositoryProvider).dailyRevenue(membership.business.id, range.from, range.to);
});

final reportSalesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final range = ref.watch(reportDateRangeProvider);
  return ref.watch(reportsRepositoryProvider).salesForRange(membership.business.id, range.from, range.to);
});

/// Today's summary for the Overview tab -- independent of the Reports
/// screen's own (user-adjustable) date range provider above.
final todaySummaryProvider = FutureProvider.autoDispose<ReportSummary>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return ReportSummary.zero;
  final today = DateRangeSelection.today();
  return ref.watch(reportsRepositoryProvider).summaryForRange(membership.business.id, today.from, today.to);
});
