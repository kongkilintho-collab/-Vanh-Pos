import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/business_role.dart';
import '../../../shared/models/sale_item.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/pos_providers.dart';
import 'sales_providers.dart';

Color statusColorFor(String status) => switch (status) {
      'VOIDED' => AppColors.danger,
      'REFUNDED' => AppColors.warning,
      _ => AppColors.success,
    };

String statusLabelFor(String status) => switch (status) {
      'VOIDED' => 'Voided',
      'REFUNDED' => 'Refunded',
      _ => 'Completed',
    };

class SaleDetailScreen extends ConsumerStatefulWidget {
  final String saleId;

  const SaleDetailScreen({super.key, required this.saleId});

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _voiding = false;

  Future<void> _confirmAndVoid(String businessId) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Void this sale?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This reverses stock and commissions for this sale and marks its '
                'payment refunded. This cannot be undone.',
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: reasonController,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'Why is this sale being voided?'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(reasonController.text.trim()),
              child: const Text('Void sale'),
            ),
          ],
        );
      },
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    setState(() => _voiding = true);
    try {
      await ref.read(posRepositoryProvider).voidSale(
            businessId: businessId,
            saleId: widget.saleId,
            reason: reason,
          );
      ref.invalidate(saleDetailProvider(widget.saleId));
      ref.invalidate(salesListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale voided.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(saleDetailProvider(widget.saleId));
    final membership = ref.watch(currentMembershipProvider);
    final canVoid = (membership?.role.isAtLeast(BusinessRole.manager)) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(detailAsync.valueOrNull?.sale.receiptNumber ?? 'Sale')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
        ),
        data: (detail) {
          final sale = detail.sale;
          final isVoided = sale.status != 'COMPLETED';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: statusColorFor(sale.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  statusLabelFor(sale.status),
                  style: AppTextStyles.captionStrong.copyWith(color: statusColorFor(sale.status)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(DateFormat('MMM d, y · h:mm a').format(sale.createdAt.toLocal()),
                  style: AppTextStyles.body.copyWith(color: AppColors.muted)),
              const Divider(height: AppSpacing.xxl),
              for (final item in detail.items) _SaleItemRow(item: item),
              const Divider(height: AppSpacing.xxl),
              _Row(label: 'Subtotal', value: formatMoney(sale.subtotal)),
              if (sale.discountAmount.toDouble() > 0) _Row(label: 'Discount', value: '-${formatMoney(sale.discountAmount)}'),
              if (sale.taxAmount.toDouble() > 0) _Row(label: 'Tax', value: formatMoney(sale.taxAmount)),
              _Row(label: 'Total', value: formatMoney(sale.totalAmount), strong: true),
              const SizedBox(height: AppSpacing.sm),
              _Row(label: 'Paid', value: formatMoney(sale.paidAmount)),
              _Row(label: 'Change', value: formatMoney(sale.changeAmount)),
              if (isVoided) ...[
                const Divider(height: AppSpacing.xxl),
                Text('Void details', style: AppTextStyles.bodyStrong),
                const SizedBox(height: AppSpacing.xs),
                if (sale.voidReason != null) Text(sale.voidReason!, style: AppTextStyles.body),
                if (sale.voidedAt != null)
                  Text(
                    DateFormat('MMM d, y · h:mm a').format(sale.voidedAt!.toLocal()),
                    style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                  ),
              ],
              if (!isVoided && canVoid) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton.tonalIcon(
                  onPressed: _voiding ? null : () => _confirmAndVoid(membership!.business.id),
                  icon: _voiding
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.block_outlined, size: 18),
                  label: Text(_voiding ? 'Voiding…' : 'Void sale'),
                  style: FilledButton.styleFrom(foregroundColor: AppColors.danger),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SaleItemRow extends StatelessWidget {
  final SaleItem item;

  const _SaleItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.nameSnapshot}${item.quantity > 1 ? '  x${item.quantity}' : ''}',
              style: AppTextStyles.body,
            ),
          ),
          Text(formatMoney(item.subtotal), style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _Row({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final style = strong ? AppTextStyles.bodyStrong : AppTextStyles.body;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style.copyWith(color: strong ? null : AppColors.muted)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
