import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/payment_method.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/pos_providers.dart';
import 'sales_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Phase 3 (Deposit / Outstanding Balance): records an additional payment
/// against a PARTIAL sale via record_sale_payment (see
/// supabase/migrations/0044_record_sale_payment_rpc.sql). The outstanding
/// balance shown here is only a display hint pre-filled from the last known
/// server value -- the RPC itself recomputes and enforces the real balance
/// server-side, so a stale/concurrent read here can never result in an
/// overpayment actually being accepted (see the RPC's own FOR UPDATE
/// locking). After a successful call, the caller must invalidate/refetch
/// saleDetailProvider -- this sheet never assumes success locally.
Future<bool?> showSettlePaymentSheet(
  BuildContext context, {
  required String saleId,
  required Decimal outstandingBalance,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SettlePaymentSheet(saleId: saleId, outstandingBalance: outstandingBalance),
  );
}

class _SettlePaymentSheet extends ConsumerStatefulWidget {
  final String saleId;
  final Decimal outstandingBalance;

  const _SettlePaymentSheet({required this.saleId, required this.outstandingBalance});

  @override
  ConsumerState<_SettlePaymentSheet> createState() => _SettlePaymentSheetState();
}

class _SettlePaymentSheetState extends ConsumerState<_SettlePaymentSheet> {
  late final _amountController = TextEditingController(text: widget.outstandingBalance.toString());
  final _referenceController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    final amount = Decimal.tryParse(_amountController.text.trim());
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _error = context.l10n.posPaymentInsufficient);
      return;
    }
    // Immediate UX feedback only -- record_sale_payment enforces this
    // server-side regardless, from the authoritative sum of payments, not
    // from this widget's outstandingBalance snapshot.
    if (amount > widget.outstandingBalance) {
      setState(() => _error = context.l10n.salesSettleAmountExceedsBalance);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(posRepositoryProvider).recordSalePayment(
            businessId: businessId,
            saleId: widget.saleId,
            paymentMethod: _paymentMethod.dbValue,
            amount: amount.toString(),
            reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
          );
      ref.invalidate(saleDetailProvider(widget.saleId));
      ref.invalidate(salesListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.salesSettleBalanceTitle, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.l10n.salesRowOutstanding}: ${formatMoney(widget.outstandingBalance)}',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.l10n.salesSettleAmountLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _paymentMethod,
              decoration: InputDecoration(labelText: context.l10n.posPaymentMethod),
              items: PaymentMethod.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.label(context.l10n))))
                  .toList(),
              onChanged: (m) => setState(() => _paymentMethod = m ?? _paymentMethod),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _referenceController,
              decoration: InputDecoration(labelText: context.l10n.salesSettleReferenceOptionalLabel),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: context.l10n.salesSettleSubmitAction,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
