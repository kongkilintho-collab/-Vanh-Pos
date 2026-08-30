import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/sale.dart';
import '../../../shared/models/staff_member.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../domain/cart_line.dart';
import 'cart_controller.dart';
import 'customer_picker_sheet.dart';
import 'pos_providers.dart';
import 'receipt_sheet.dart';

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _submitting = false;
  String? _error;

  Future<void> _checkout() async {
    final cart = ref.read(cartControllerProvider);
    final membership = ref.read(currentMembershipProvider);
    if (membership == null || cart.isEmpty || _submitting) return;

    // Immediate UX feedback only -- complete_sale enforces this
    // server-side regardless (see 0024_complete_sale_price_and_payment_integrity.sql),
    // so this is not the security boundary, just an earlier, friendlier error.
    if (cart.paidAmount < cart.total) {
      setState(() => _error = 'Payment amount cannot be less than the sale total.');
      return;
    }

    setState(() {
      _submitting = true;
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
        paymentMethod: cart.paymentMethod.dbValue,
        paidAmount: cart.paidAmount.toString(),
        idempotencyKey: cart.idempotencyKey,
      );
      final sale = Sale.fromJson(row);

      if (!mounted) return;
      final user = ref.read(currentUserProvider);
      final lines = cart.lines;
      final customer = cart.customer;
      final paymentMethod = cart.paymentMethod;

      ref.read(cartControllerProvider.notifier).reset();

      await showReceiptSheet(
        context,
        sale: sale,
        business: membership.business,
        lines: lines,
        customer: customer,
        paymentMethod: paymentMethod,
        cashierName: user?.email ?? 'Cashier',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final staffAsync = ref.watch(staffListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: OutlinedButton.icon(
            onPressed: () async {
              final selected = await showCustomerPickerSheet(context);
              if (selected != null) {
                ref.read(cartControllerProvider.notifier).setCustomer(selected);
              }
            },
            icon: const Icon(Icons.person_outline, size: 18),
            label: Text(cart.customer?.name ?? 'Walk-in customer'),
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text(
                    'Cart is empty\nTap a service or product to add it',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    for (final line in cart.lines)
                      _CartLineTile(line: line, staff: staffAsync.valueOrNull ?? const []),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.md),
              ],
              _TotalsRow(label: 'Subtotal', value: cart.subtotal),
              _DiscountRow(),
              if (cart.taxEnabled) _TotalsRow(label: 'Tax', value: cart.taxAmount),
              const SizedBox(height: AppSpacing.xs),
              _TotalsRow(label: 'Total', value: cart.total, strong: true),
              const SizedBox(height: AppSpacing.md),
              _PaymentMethodSelector(),
              const SizedBox(height: AppSpacing.sm),
              _PaidAmountField(),
              const SizedBox(height: AppSpacing.xs),
              _TotalsRow(label: 'Change', value: cart.change),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Complete sale',
                onPressed: cart.isEmpty ? null : _checkout,
                loading: _submitting,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  final CartLine line;
  final List<StaffMember> staff;

  const _CartLineTile({required this.line, required this.staff});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cartControllerProvider.notifier);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(line.name, style: AppTextStyles.bodyStrong)),
                Text(formatMoney(line.subtotal), style: AppTextStyles.bodyStrong),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _QuantityStepper(
                  quantity: line.quantity,
                  onChanged: (q) => controller.setQuantity(line.key, q),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                  onPressed: () => controller.removeLine(line.key),
                  tooltip: 'Remove',
                ),
              ],
            ),
            if (staff.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String?>(
                initialValue: line.staffId,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Staff (for commission)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Unassigned')),
                  for (final s in staff) DropdownMenuItem(value: s.userId, child: Text(s.fullName)),
                ],
                onChanged: (v) => controller.setLineStaff(
                  line.key,
                  v,
                  v == null ? null : staff.firstWhere((s) => s.userId == v).fullName,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: () => onChanged(quantity - 1),
          visualDensity: VisualDensity.compact,
        ),
        Text('$quantity', style: AppTextStyles.bodyStrong),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 18),
          onPressed: () => onChanged(quantity + 1),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String label;
  final Decimal value;
  final bool strong;

  const _TotalsRow({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final style = strong ? AppTextStyles.numeric : AppTextStyles.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: (strong ? AppTextStyles.bodyStrong : AppTextStyles.body)),
          Text(formatMoney(value), style: style),
        ],
      ),
    );
  }
}

class _DiscountRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DiscountRow> createState() => _DiscountRowState();
}

class _DiscountRowState extends ConsumerState<_DiscountRow> {
  late final _controller = TextEditingController(
    text: ref.read(cartControllerProvider).discountAmount == Decimal.zero
        ? ''
        : ref.read(cartControllerProvider).discountAmount.toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('Discount', style: AppTextStyles.body)),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true, hintText: '0'),
            onChanged: (v) {
              final parsed = Decimal.tryParse(v.trim());
              ref.read(cartControllerProvider.notifier).setDiscount(parsed ?? Decimal.zero);
            },
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    return DropdownButtonFormField<PaymentMethod>(
      initialValue: cart.paymentMethod,
      decoration: const InputDecoration(labelText: 'Payment method'),
      items: PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label))).toList(),
      onChanged: (m) {
        if (m != null) ref.read(cartControllerProvider.notifier).setPaymentMethod(m);
      },
    );
  }
}

class _PaidAmountField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PaidAmountField> createState() => _PaidAmountFieldState();
}

class _PaidAmountFieldState extends ConsumerState<_PaidAmountField> {
  final _controller = TextEditingController();
  Decimal? _lastTotal;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    // Keep the field pre-filled with the exact total (the common case: paid
    // in full) until the cashier explicitly types a different amount.
    if (_lastTotal != cart.total && cart.paidAmount == Decimal.zero) {
      _controller.text = cart.total == Decimal.zero ? '' : cart.total.toString();
      ref.read(cartControllerProvider.notifier).setPaidAmount(cart.total);
    }
    _lastTotal = cart.total;

    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Amount paid (LAK)'),
      onChanged: (v) {
        final parsed = Decimal.tryParse(v.trim());
        ref.read(cartControllerProvider.notifier).setPaidAmount(parsed ?? Decimal.zero);
      },
    );
  }
}
