import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/report_summary.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'reports_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// The "Overview" tab's real-metrics content (Day 5), replacing the
/// static placeholder that stood in for it through Days 1-4.
class DashboardOverviewScreen extends ConsumerWidget {
  const DashboardOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(todaySummaryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.navOverview, style: AppTextStyles.displayMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.reportsTodayTagline,
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xl),
          summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                ErrorBanner(message: friendlyError(err, context.l10n)),
            data: (summary) => _OverviewMetrics(summary: summary),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetrics extends StatelessWidget {
  final ReportSummary summary;

  const _OverviewMetrics({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _MetricTile(
          label: context.l10n.reportsTodaySales,
          value: formatMoney(summary.revenue),
          sublabel: context.l10n.reportsSalesCount(summary.salesCount),
        ),
        _MetricTile(
          label: context.l10n.reportsCommission,
          value: formatMoney(summary.commissionTotal),
        ),
        _MetricTile(
          label: context.l10n.reportsExpenses,
          value: formatMoney(summary.expenseTotal),
        ),
        _MetricTile(
          label: context.l10n.reportsEstimatedProfit,
          value: formatMoney(summary.profit),
          valueColor: summary.profit < Decimal.zero
              ? AppColors.danger
              : AppColors.success,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final Color? valueColor;

  const _MetricTile({
    required this.label,
    required this.value,
    this.sublabel,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTextStyles.numeric.copyWith(color: valueColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  sublabel!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
