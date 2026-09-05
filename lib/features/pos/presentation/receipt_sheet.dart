import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/hardware/hardware_providers.dart';
import '../../../core/hardware/models/hardware_result.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/business.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/sale.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../domain/cart_line.dart';

Future<void> showReceiptSheet(
  BuildContext context, {
  required Sale sale,
  required Business business,
  required List<CartLine> lines,
  required Customer? customer,
  required PaymentMethod paymentMethod,
  required String cashierName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => ReceiptSheet(
      sale: sale,
      business: business,
      lines: lines,
      customer: customer,
      paymentMethod: paymentMethod,
      cashierName: cashierName,
    ),
  );
}

class ReceiptSheet extends StatelessWidget {
  final Sale sale;
  final Business business;
  final List<CartLine> lines;
  final Customer? customer;
  final PaymentMethod paymentMethod;
  final String cashierName;

  const ReceiptSheet({
    super.key,
    required this.sale,
    required this.business,
    required this.lines,
    required this.customer,
    required this.paymentMethod,
    required this.cashierName,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      context.l10n.posReceiptSaleComplete,
                      style: AppTextStyles.headline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    business.name,
                    style: AppTextStyles.subtitle,
                    textAlign: TextAlign.center,
                  ),
                  if (business.phone != null)
                    Text(
                      business.phone!,
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _ReceiptRow(
                    label: context.l10n.posReceiptReceipt,
                    value: sale.receiptNumber,
                  ),
                  _ReceiptRow(
                    label: context.l10n.posReceiptDate,
                    value: DateFormat(
                      'yMMMd · h:mm a',
                    ).format(sale.createdAt.toLocal()),
                  ),
                  _ReceiptRow(
                    label: context.l10n.posReceiptCashier,
                    value: cashierName,
                  ),
                  _ReceiptRow(
                    label: context.l10n.posReceiptCustomer,
                    value: customer?.name ?? context.l10n.posReceiptWalkIn,
                  ),
                  const Divider(height: AppSpacing.xxl),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${line.name}${line.quantity > 1 ? '  x${line.quantity}' : ''}',
                              style: AppTextStyles.body,
                            ),
                          ),
                          Text(
                            formatMoney(line.subtotal),
                            style: AppTextStyles.body,
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: AppSpacing.xxl),
                  _ReceiptRow(
                    label: context.l10n.posSubtotal,
                    value: formatMoney(sale.subtotal),
                  ),
                  if (sale.discountAmount.toDouble() > 0)
                    _ReceiptRow(
                      label: context.l10n.posDiscount,
                      value: '-${formatMoney(sale.discountAmount)}',
                    ),
                  if (sale.taxAmount.toDouble() > 0)
                    _ReceiptRow(
                      label: context.l10n.posTax,
                      value: formatMoney(sale.taxAmount),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  _ReceiptRow(
                    label: context.l10n.posTotal,
                    value: formatMoney(sale.totalAmount),
                    strong: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ReceiptRow(
                    label: context.l10n.posReceiptPaidVia(
                      paymentMethod.label(context.l10n),
                    ),
                    value: formatMoney(sale.paidAmount),
                  ),
                  _ReceiptRow(
                    label: context.l10n.posChange,
                    value: formatMoney(sale.changeAmount),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      context.l10n.posReceiptThankYou,
                      style: AppTextStyles.subtitle.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    _PrintReceiptButton(
                      sale: sale,
                      business: business,
                      lines: lines,
                      customer: customer,
                      paymentMethod: paymentMethod,
                      cashierName: cashierName,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: context.l10n.posReceiptNewSale,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Optional print action. This is a side effect of an already-completed
/// sale: a printer failure here only updates this button's own status text
/// -- it never touches the sale, never retries `complete_sale`, and never
/// blocks "New sale".
class _PrintReceiptButton extends ConsumerStatefulWidget {
  final Sale sale;
  final Business business;
  final List<CartLine> lines;
  final Customer? customer;
  final PaymentMethod paymentMethod;
  final String cashierName;

  const _PrintReceiptButton({
    required this.sale,
    required this.business,
    required this.lines,
    required this.customer,
    required this.paymentMethod,
    required this.cashierName,
  });

  @override
  ConsumerState<_PrintReceiptButton> createState() => _PrintReceiptButtonState();
}

class _PrintReceiptButtonState extends ConsumerState<_PrintReceiptButton> {
  bool _printing = false;
  String? _statusMessage;

  Future<void> _print() async {
    final hardwareAsync = ref.read(hardwareServiceProvider);
    final hardware = hardwareAsync.valueOrNull;
    if (hardware == null) return;

    setState(() {
      _printing = true;
      _statusMessage = null;
    });

    final l10n = context.l10n;
    final result = await hardware.printer.printSaleReceipt(
      sale: widget.sale,
      business: widget.business,
      lines: widget.lines,
      customer: widget.customer,
      paymentMethod: widget.paymentMethod,
      cashierName: widget.cashierName,
      l10n: l10n,
    );

    if (!mounted) return;
    setState(() {
      _printing = false;
      _statusMessage = switch (result.outcome) {
        PrintOutcome.confirmed => l10n.posReceiptPrintConfirmed,
        PrintOutcome.uncertain => l10n.posReceiptPrintUncertain,
        PrintOutcome.failed => result.failure?.code == HardwareErrorCode.notConfigured
            ? l10n.posReceiptPrintNotConfigured
            : l10n.posReceiptPrintFailed,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final hardwareAsync = ref.watch(hardwareServiceProvider);
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _printing || !hardwareAsync.hasValue ? null : _print,
          icon: _printing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(
            _printing ? context.l10n.posReceiptPrinting : context.l10n.posReceiptPrint,
          ),
        ),
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _statusMessage!,
              style: AppTextStyles.caption.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

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
