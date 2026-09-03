import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/sale.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../sales/presentation/sale_detail_screen.dart' show paymentStatusLabelFor;
import 'cart_controller.dart';
import 'pos_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Phase 3 (Deposit / Outstanding Balance) — the explicit, opt-in entry
/// point for starting a sale with a partial initial payment, distinct from
/// CartPanel's own "Complete sale" full-payment checkout. Reads the SAME
/// cartControllerProvider state CartPanel reads (so the cart contents are
/// identical either way) but never touches cart_panel.dart itself.
///
/// Calls complete_sale with allowPartialPayment: true (see
/// PosRepository.completeSale / supabase/migrations/0043_complete_sale_partial_payment.sql).
/// The server remains the sole authority on the sale total, paid amount,
/// and payment status: the "remaining balance" shown here as the cashier
/// types is a client-side display hint only, computed from the same
/// cart.total the checkout button already trusts (itself server-verified
/// on every prior line-price resolution) minus a not-yet-submitted local
/// number -- it is never sent as a field the server trusts, and the result
/// screen redisplays only what the server actually returned, not this
/// local estimate.
Future<void> showDepositCheckoutSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DepositCheckoutSheet(),
  );
}

class _DepositCheckoutSheet extends ConsumerStatefulWidget {
  const _DepositCheckoutSheet();

  @override
  ConsumerState<_DepositCheckoutSheet> createState() => _DepositCheckoutSheetState();
}

class _DepositCheckoutSheetState extends ConsumerState<_DepositCheckoutSheet> {
  final _amountController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _loading = false;
  String? _error;
  Sale? _result;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final cart = ref.read(cartControllerProvider);
    final membership = ref.read(currentMembershipProvider);
    if (membership == null || cart.isEmpty || _loading) return;

    final amount = Decimal.tryParse(_amountController.text.trim());
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _error = context.l10n.posDepositAmountRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(posRepositoryProvider);
      final branchId = await repo.primaryBranchId(membership.business.id);

      final row = await repo.completeSale(
        businessId: membership.business.id,
        branchId: branchId,
        customerId: cart.customer?.id,
        items: cart.lines.map((l) => l.toRpcJson()).toList(),
        discountAmount: cart.discountAmount.toString(),
        taxAmount: cart.taxAmount.toString(),
        paymentMethod: _paymentMethod.dbValue,
        paidAmount: amount.toString(),
        idempotencyKey: cart.idempotencyKey,
        allowPartialPayment: true,
      );
      final sale = Sale.fromJson(row);

      if (!mounted) return;
      ref.read(cartControllerProvider.notifier).reset();
      setState(() => _result = sale);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return _DepositResultView(sale: result);
    }

    final cart = ref.watch(cartControllerProvider);
    final enteredAmount = Decimal.tryParse(_amountController.text.trim());
    final remaining = enteredAmount == null
        ? cart.total
        : (cart.total - enteredAmount).clamp(Decimal.zero, cart.total);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.posDepositTitle, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.l10n.posTotal}: ${formatMoney(cart.total)}',
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
              decoration: InputDecoration(labelText: context.l10n.posDepositAmountLabel),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${context.l10n.posDepositRemainingBalance}: ${formatMoney(remaining)}',
              style: AppTextStyles.body,
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
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: context.l10n.posDepositConfirmAction,
              onPressed: cart.isEmpty ? null : _confirm,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositResultView extends StatelessWidget {
  final Sale sale;

  const _DepositResultView({required this.sale});

  @override
  Widget build(BuildContext context) {
    // Everything below comes straight from the server's own response
    // (Sale.fromJson(row) from complete_sale's return value) -- nothing
    // here is a locally recomputed or assumed value.
    final outstanding = sale.totalAmount - sale.paidAmount;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.posDepositResultTitle, style: AppTextStyles.headline),
          const SizedBox(height: AppSpacing.lg),
          _ResultRow(label: context.l10n.posTotal, value: formatMoney(sale.totalAmount)),
          _ResultRow(label: context.l10n.salesRowPaid, value: formatMoney(sale.paidAmount)),
          if (outstanding > Decimal.zero)
            _ResultRow(label: context.l10n.salesRowOutstanding, value: formatMoney(outstanding)),
          _ResultRow(
            label: context.l10n.posDepositResultPaymentStatus,
            value: paymentStatusLabelFor(sale.paymentStatus, context.l10n) ?? sale.paymentStatus,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: context.l10n.posDepositDoneAction,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body),
          Text(value, style: AppTextStyles.bodyStrong),
        ],
      ),
    );
  }
}
