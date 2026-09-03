import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/business_role.dart';
import '../../../shared/models/payment.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/sale_item.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/pos_providers.dart';
import 'sales_providers.dart';
import 'settle_payment_sheet.dart';
import '../../../l10n/l10n_extensions.dart';

Color statusColorFor(String status) => switch (status) {
  'VOIDED' => AppColors.danger,
  'REFUNDED' => AppColors.warning,
  _ => AppColors.success,
};

String statusLabelFor(String status, AppLocalizations l10n) => switch (status) {
  'VOIDED' => l10n.salesStatusVoided,
  'REFUNDED' => l10n.salesStatusRefunded,
  _ => l10n.salesStatusCompleted,
};

/// Phase 3 (Deposit / Outstanding Balance): sales.payment_status badge --
/// shown only when it says something the sale.status badge above doesn't
/// already convey (PARTIAL or PENDING); a COMPLETED/REFUNDED payment_status
/// is redundant with a COMPLETED/VOIDED sale.status and is not shown twice.
Color? paymentStatusColorFor(String paymentStatus) => switch (paymentStatus) {
  'PARTIAL' => AppColors.warning,
  'PENDING' => AppColors.warning,
  _ => null,
};

String? paymentStatusLabelFor(String paymentStatus, AppLocalizations l10n) => switch (paymentStatus) {
  'PARTIAL' => l10n.salesStatusPartial,
  'PENDING' => l10n.salesStatusPending,
  _ => null,
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
          title: Text(context.l10n.salesVoidConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.salesVoidConfirmBody,
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: reasonController,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.salesVoidReasonLabel,
                  hintText: context.l10n.salesVoidReasonHint,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(reasonController.text.trim()),
              child: Text(context.l10n.salesVoidAction),
            ),
          ],
        );
      },
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    setState(() => _voiding = true);
    try {
      await ref
          .read(posRepositoryProvider)
          .voidSale(
            businessId: businessId,
            saleId: widget.saleId,
            reason: reason,
          );
      ref.invalidate(saleDetailProvider(widget.saleId));
      ref.invalidate(salesListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.salesVoidedSnackbar)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e, context.l10n))));
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  Future<void> _settle(String saleId, Decimal outstandingBalance) async {
    final success = await showSettlePaymentSheet(
      context,
      saleId: saleId,
      outstandingBalance: outstandingBalance,
    );
    if (success == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.salesSettleSuccessSnackbar)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(saleDetailProvider(widget.saleId));
    final membership = ref.watch(currentMembershipProvider);
    final canVoid = (membership?.role.isAtLeast(BusinessRole.manager)) ?? false;
    final canSettle = (membership?.role.isAtLeast(BusinessRole.cashier)) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detailAsync.valueOrNull?.sale.receiptNumber ??
              context.l10n.salesDetailFallbackTitle,
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (detail) {
          final sale = detail.sale;
          final isVoided = sale.status != 'COMPLETED';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: statusColorFor(sale.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      statusLabelFor(sale.status, context.l10n),
                      style: AppTextStyles.captionStrong.copyWith(
                        color: statusColorFor(sale.status),
                      ),
                    ),
                  ),
                  if (paymentStatusLabelFor(sale.paymentStatus, context.l10n) != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: paymentStatusColorFor(sale.paymentStatus)!.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        paymentStatusLabelFor(sale.paymentStatus, context.l10n)!,
                        style: AppTextStyles.captionStrong.copyWith(
                          color: paymentStatusColorFor(sale.paymentStatus),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                DateFormat(
                  'MMM d, y · h:mm a',
                ).format(sale.createdAt.toLocal()),
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
              const Divider(height: AppSpacing.xxl),
              for (final item in detail.items) _SaleItemRow(item: item),
              const Divider(height: AppSpacing.xxl),
              _Row(
                label: context.l10n.posSubtotal,
                value: formatMoney(sale.subtotal),
              ),
              if (sale.discountAmount.toDouble() > 0)
                _Row(
                  label: context.l10n.posDiscount,
                  value: '-${formatMoney(sale.discountAmount)}',
                ),
              if (sale.taxAmount.toDouble() > 0)
                _Row(
                  label: context.l10n.posTax,
                  value: formatMoney(sale.taxAmount),
                ),
              _Row(
                label: context.l10n.posTotal,
                value: formatMoney(sale.totalAmount),
                strong: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Row(
                label: context.l10n.salesRowPaid,
                value: formatMoney(sale.paidAmount),
              ),
              _Row(
                label: context.l10n.posChange,
                value: formatMoney(sale.changeAmount),
              ),
              if (sale.paymentStatus == 'PARTIAL')
                _Row(
                  label: context.l10n.salesRowOutstanding,
                  value: formatMoney(sale.totalAmount - sale.paidAmount),
                  strong: true,
                ),
              const Divider(height: AppSpacing.xxl),
              Text(context.l10n.salesPaymentHistoryTitle, style: AppTextStyles.bodyStrong),
              const SizedBox(height: AppSpacing.sm),
              if (detail.payments.isEmpty)
                Text(
                  context.l10n.salesNoPayments,
                  style: AppTextStyles.body.copyWith(color: AppColors.muted),
                )
              else
                for (final payment in detail.payments) _PaymentHistoryRow(payment: payment),
              if (sale.paymentStatus == 'PARTIAL' && !isVoided && canSettle) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () => _settle(sale.id, sale.totalAmount - sale.paidAmount),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(context.l10n.salesSettleBalanceAction),
                ),
              ],
              if (isVoided) ...[
                const Divider(height: AppSpacing.xxl),
                Text(
                  context.l10n.salesVoidDetailsTitle,
                  style: AppTextStyles.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (sale.voidReason != null)
                  Text(sale.voidReason!, style: AppTextStyles.body),
                if (sale.voidedAt != null)
                  Text(
                    DateFormat(
                      'MMM d, y · h:mm a',
                    ).format(sale.voidedAt!.toLocal()),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
              ],
              if (!isVoided && canVoid) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton.tonalIcon(
                  onPressed: _voiding
                      ? null
                      : () => _confirmAndVoid(membership!.business.id),
                  icon: _voiding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.block_outlined, size: 18),
                  label: Text(
                    _voiding
                        ? context.l10n.salesVoiding
                        : context.l10n.salesVoidAction,
                  ),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
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

class _PaymentHistoryRow extends StatelessWidget {
  final Payment payment;

  const _PaymentHistoryRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final method = PaymentMethod.fromDb(payment.paymentMethod).label(context.l10n);
    final refunded = payment.status == 'REFUNDED';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMM d, y · h:mm a').format(payment.createdAt.toLocal()),
                  style: AppTextStyles.body,
                ),
                Text(
                  payment.reference != null && payment.reference!.isNotEmpty
                      ? '$method · ${payment.reference}'
                      : method,
                  style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(payment.amount),
            style: AppTextStyles.body.copyWith(
              color: refunded ? AppColors.muted : null,
              decoration: refunded ? TextDecoration.lineThrough : null,
            ),
          ),
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
          Text(
            label,
            style: style.copyWith(color: strong ? null : AppColors.muted),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}
