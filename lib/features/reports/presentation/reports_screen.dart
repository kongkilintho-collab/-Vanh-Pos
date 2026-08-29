import 'package:data_table_2/data_table_2.dart';
import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/csv_export.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/report_summary.dart';
import '../../../shared/widgets/date_range_filter.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'reports_providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final sales = await ref.read(reportSalesProvider.future);
    final rows = <List<String>>[
      ['Receipt', 'Date', 'Amount', 'Payment status'],
      for (final sale in sales)
        [
          sale['receipt_number'] as String,
          DateTime.parse(sale['created_at'] as String).toLocal().toIso8601String(),
          sale['total_amount'].toString(),
          sale['payment_status'] as String,
        ],
    ];
    await Clipboard.setData(ClipboardData(text: toCsv(rows)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied to clipboard as CSV.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportDateRangeProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DateRangeFilterBar(
                    selection: range,
                    onChanged: (s) => ref.read(reportDateRangeProvider.notifier).state = s,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _export(context, ref),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorBanner(message: friendlyError(err)),
              data: (summary) => _SummaryRow(summary: summary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('Revenue by day', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(height: 220, child: _RevenueChart()),
            const SizedBox(height: AppSpacing.xxl),
            Text('Sales in range', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(height: 400, child: _SalesTable()),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final ReportSummary summary;

  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _StatCard(label: 'Revenue', value: formatMoney(summary.revenue)),
        _StatCard(label: 'Cost of goods sold', value: formatMoney(summary.cogs)),
        _StatCard(label: 'Commission', value: formatMoney(summary.commissionTotal)),
        _StatCard(label: 'Expenses', value: formatMoney(summary.expenseTotal)),
        _StatCard(
          label: 'Estimated profit',
          value: formatMoney(summary.profit),
          valueColor: summary.profit < Decimal.zero ? AppColors.danger : AppColors.success,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.muted)),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: AppTextStyles.subtitle.copyWith(color: valueColor), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueChart extends ConsumerWidget {
  const _RevenueChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(dailyRevenueProvider);

    return dailyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorBanner(message: friendlyError(err)),
      data: (daily) {
        if (daily.isEmpty) {
          return Center(
            child: Text('No sales in this range yet.', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
          );
        }

        final maxRevenue = daily.map((d) => d.revenue.toDouble()).reduce((a, b) => a > b ? a : b);

        return BarChart(
          BarChartData(
            maxY: maxRevenue <= 0 ? 1 : maxRevenue * 1.2,
            barGroups: [
              for (var i = 0; i < daily.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(toY: daily[i].revenue.toDouble(), color: AppColors.primary, width: 14),
                  ],
                ),
            ],
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= daily.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(DateFormat('M/d').format(daily[index].date), style: AppTextStyles.caption),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
          ),
        );
      },
    );
  }
}

class _SalesTable extends ConsumerWidget {
  const _SalesTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(reportSalesProvider);

    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorBanner(message: friendlyError(err)),
      data: (sales) {
        if (sales.isEmpty) {
          return Center(
            child: Text('No sales in this range yet.', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
          );
        }

        return DataTable2(
          columnSpacing: AppSpacing.lg,
          minWidth: 500,
          columns: const [
            DataColumn2(label: Text('Receipt')),
            DataColumn2(label: Text('Date')),
            DataColumn2(label: Text('Status')),
            DataColumn2(label: Text('Amount'), numeric: true),
          ],
          rows: [
            for (final sale in sales)
              DataRow2(cells: [
                DataCell(Text(sale['receipt_number'] as String)),
                DataCell(Text(DateFormat('MMM d, y · h:mm a').format(DateTime.parse(sale['created_at'] as String).toLocal()))),
                DataCell(Text(sale['payment_status'] as String)),
                DataCell(Text(formatMoney(Decimal.parse(sale['total_amount'].toString())))),
              ]),
          ],
        );
      },
    );
  }
}
