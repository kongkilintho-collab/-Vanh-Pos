import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/commission_kind.dart';
import '../../../shared/models/service.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'service_providers.dart';

Future<void> showServiceFormSheet(BuildContext context, {Service? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ServiceFormSheet(existing: existing),
  );
}

class _ServiceFormSheet extends ConsumerStatefulWidget {
  final Service? existing;

  const _ServiceFormSheet({this.existing});

  @override
  ConsumerState<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends ConsumerState<_ServiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
  late final _priceController = TextEditingController(text: widget.existing?.price.toString() ?? '');
  late final _durationController =
      TextEditingController(text: (widget.existing?.durationMinutes ?? 30).toString());
  late final _commissionValueController =
      TextEditingController(text: widget.existing?.commissionValue.toString() ?? '0');
  late CommissionKind _commissionType = widget.existing?.commissionType ?? CommissionKind.percentage;
  late bool _active = widget.existing?.active ?? true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _commissionValueController.dispose();
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
      final service = Service(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        categoryId: widget.existing?.categoryId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: Decimal.parse(_priceController.text.trim()),
        durationMinutes: int.parse(_durationController.text.trim()),
        commissionType: _commissionType,
        commissionValue: Decimal.parse(_commissionValueController.text.trim()),
        active: _active,
      );

      final repo = ref.read(serviceRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(service);
      } else {
        await repo.update(service);
      }

      ref.invalidate(servicesListProvider);
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
              Text(isEditing ? 'Edit service' : 'Add service', style: AppTextStyles.headline),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Service name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price (LAK)'),
                      validator: (v) {
                        final parsed = Decimal.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < Decimal.zero) return 'Enter a valid price';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Duration (min)'),
                      validator: (v) {
                        final parsed = int.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed <= 0) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<CommissionKind>(
                      initialValue: _commissionType,
                      decoration: const InputDecoration(labelText: 'Commission type'),
                      items: CommissionKind.values
                          .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _commissionType = v ?? _commissionType),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _commissionValueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _commissionType == CommissionKind.percentage ? 'Commission %' : 'Commission (LAK)',
                      ),
                      validator: (v) {
                        final parsed = Decimal.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < Decimal.zero) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing ? 'Save changes' : 'Add service',
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
