import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/sale.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'sale_detail_screen.dart';
import 'sales_providers.dart';

Color _statusColor(String status) => switch (status) {
      'VOIDED' => AppColors.danger,
      'REFUNDED' => AppColors.warning,
      _ => AppColors.success,
    };

String _statusLabel(String status) => switch (status) {
      'VOIDED' => 'Voided',
      'REFUNDED' => 'Refunded',
      _ => 'Completed',
    };

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search by receipt number',
              ),
              onChanged: (v) => ref.read(salesSearchQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
              ),
              data: (sales) {
                if (sales.isEmpty) {
                  return Center(
                    child: Text('No sales found.', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  itemCount: sales.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _SaleTile(sale: sales[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final Sale sale;

  const _SaleTile({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        title: Text(sale.receiptNumber, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          DateFormat('MMM d, y · h:mm a').format(sale.createdAt.toLocal()),
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(sale.totalAmount), style: AppTextStyles.bodyStrong),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
              decoration: BoxDecoration(
                color: _statusColor(sale.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(_statusLabel(sale.status), style: AppTextStyles.caption.copyWith(color: _statusColor(sale.status))),
            ),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id)),
        ),
      ),
    );
  }
}
