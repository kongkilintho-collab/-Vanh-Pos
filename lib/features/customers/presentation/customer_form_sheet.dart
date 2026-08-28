import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/customer.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'customer_providers.dart';

Future<void> showCustomerFormSheet(BuildContext context, {Customer? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomerFormSheet(existing: existing),
  );
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  final Customer? existing;

  const _CustomerFormSheet({this.existing});

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _notesController = TextEditingController(text: widget.existing?.notes ?? '');
  String? _gender;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gender = widget.existing?.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
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
      final customer = Customer(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        gender: _gender,
        birthday: widget.existing?.birthday,
        notes: _notesController.text.trim(),
        totalSpent: widget.existing?.totalSpent ?? Decimal.zero,
        visitCount: widget.existing?.visitCount ?? 0,
        lastVisitAt: widget.existing?.lastVisitAt,
        active: widget.existing?.active ?? true,
      );

      final repo = ref.read(customerRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(customer);
      } else {
        await repo.update(customer);
      }

      ref.invalidate(customersListProvider);
      if (widget.existing != null) ref.invalidate(customerDetailProvider(widget.existing!.id));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
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
              Text(isEditing ? 'Edit customer' : 'Add customer', style: AppTextStyles.headline),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender (optional)'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Not specified')),
                  DropdownMenuItem(value: 'MALE', child: Text('Male')),
                  DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing ? 'Save changes' : 'Add customer',
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
