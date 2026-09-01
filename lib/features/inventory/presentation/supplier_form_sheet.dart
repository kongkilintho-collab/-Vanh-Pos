import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/supplier.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'inventory_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showSupplierFormSheet(BuildContext context, {Supplier? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SupplierFormSheet(existing: existing),
  );
}

class _SupplierFormSheet extends ConsumerStatefulWidget {
  final Supplier? existing;

  const _SupplierFormSheet({this.existing});

  @override
  ConsumerState<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends ConsumerState<_SupplierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _phoneController = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final _emailController = TextEditingController(
    text: widget.existing?.email ?? '',
  );
  late final _addressController = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late bool _active = widget.existing?.active ?? true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supplier = Supplier(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        active: _active,
      );

      final repo = ref.read(inventoryRepositoryProvider);
      if (widget.existing == null) {
        await repo.createSupplier(supplier);
      } else {
        await repo.updateSupplier(supplier);
      }

      ref.invalidate(suppliersListProvider);
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
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing
                    ? context.l10n.invEditSupplier
                    : context.l10n.invAddSupplier,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.supplierNameLabel,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.commonRequired
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.l10n.authPhoneOptionalLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.customersEmailOptionalLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: context.l10n.customersAddressOptionalLabel,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.commonActive),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing
                    ? context.l10n.commonSaveChanges
                    : context.l10n.invAddSupplier,
                onPressed: _submit,
                loading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
