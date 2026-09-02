import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/package.dart';
import '../../../shared/models/payment_method.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/customer_picker_sheet.dart';
import 'customer_package_providers.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../../l10n/l10n_extensions.dart';

const _uuid = Uuid();

/// Package purchase does not go through CartState/complete_sale -- a
/// package doesn't fit the quantity/discount/per-line-commission shape
/// SERVICE/PRODUCT cart lines have, and purchase_package (0037) is its own
/// atomic RPC. This is a standalone sheet, not a cart addition.
Future<void> showPackagePurchaseSheet(BuildContext context, Package package) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PackagePurchaseSheet(package: package),
  );
}

class _PackagePurchaseSheet extends ConsumerStatefulWidget {
  final Package package;

  const _PackagePurchaseSheet({required this.package});

  @override
  ConsumerState<_PackagePurchaseSheet> createState() => _PackagePurchaseSheetState();
}

class _PackagePurchaseSheetState extends ConsumerState<_PackagePurchaseSheet> {
  String? _customerId;
  String? _customerName;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  late final _idempotencyKey = _uuid.v4();

  bool _loading = false;
  String? _error;

  Future<void> _pickCustomer() async {
    final customer = await showCustomerPickerSheet(context);
    if (customer != null) {
      setState(() {
        _customerId = customer.id;
        _customerName = customer.name;
      });
    }
  }

  Future<void> _submit() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    if (_customerId == null) {
      setState(() => _error = context.l10n.pkgCustomerRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(customerPackageRepositoryProvider).purchase(
            businessId: businessId,
            customerId: _customerId!,
            packageId: widget.package.id,
            paymentMethod: _paymentMethod.dbValue,
            paidAmount: widget.package.price.toString(),
            idempotencyKey: _idempotencyKey,
          );
      ref.invalidate(customerPackagesForCustomerProvider(_customerId!));
      if (mounted) Navigator.of(context).pop();
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
            Text(widget.package.name, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatMoney(widget.package.price),
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_customerName ?? context.l10n.pkgSelectCustomer),
              subtitle: Text(context.l10n.pkgCustomerRequired),
              trailing: TextButton(
                onPressed: _pickCustomer,
                child: Text(context.l10n.commonChoose),
              ),
            ),
            const Divider(),
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
              label: context.l10n.pkgPurchaseAction,
              onPressed: _customerId == null ? null : _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
