import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/package.dart';
import '../../../shared/models/package_item.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../services/presentation/service_providers.dart';
import 'package_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showPackageFormSheet(BuildContext context, {Package? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PackageFormSheet(existing: existing),
  );
}

class _DraftItem {
  String serviceId;
  int sessionCount;

  _DraftItem({required this.serviceId, required this.sessionCount});
}

class _PackageFormSheet extends ConsumerStatefulWidget {
  final Package? existing;

  const _PackageFormSheet({this.existing});

  @override
  ConsumerState<_PackageFormSheet> createState() => _PackageFormSheetState();
}

class _PackageFormSheetState extends ConsumerState<_PackageFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
  late final _priceController = TextEditingController(text: widget.existing?.price.toString() ?? '');
  late final _validityController = TextEditingController(
    text: widget.existing?.validityDays?.toString() ?? '',
  );
  late bool _active = widget.existing?.active ?? true;
  late final List<_DraftItem> _items = widget.existing?.items
          .map((i) => _DraftItem(serviceId: i.serviceId, sessionCount: i.sessionCount))
          .toList() ??
      [];

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _validityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    if (_items.isEmpty) {
      setState(() => _error = context.l10n.pkgSelectAtLeastOneService);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final package = Package(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: Decimal.parse(_priceController.text.trim()),
        validityDays: _validityController.text.trim().isEmpty
            ? null
            : int.parse(_validityController.text.trim()),
        active: _active,
      );
      final items = _items
          .map((i) => PackageItem(
                id: '',
                packageId: '',
                serviceId: i.serviceId,
                sessionCount: i.sessionCount,
              ))
          .toList();

      final repo = ref.read(packageRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(package, items);
      } else {
        await repo.update(package, items);
      }

      ref.invalidate(packagesListProvider);
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
    final servicesAsync = ref.watch(servicesListProvider);

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
                isEditing ? context.l10n.pkgEditTitle : context.l10n.pkgAddTitle,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: context.l10n.pkgNameLabel),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? context.l10n.commonRequired : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: context.l10n.pkgDescriptionOptionalLabel),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: context.l10n.pkgPriceLak),
                      validator: (v) {
                        final parsed = Decimal.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < Decimal.zero) {
                          return context.l10n.commonInvalid;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _validityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.l10n.pkgValidityDaysOptionalLabel),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null || parsed <= 0) return context.l10n.commonInvalid;
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.commonActive),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.pkgServicesLabel, style: AppTextStyles.bodyStrong),
              const SizedBox(height: AppSpacing.sm),
              servicesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(friendlyError(e, context.l10n)),
                data: (services) {
                  final active = services.where((s) => s.active).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _items[i].serviceId.isEmpty ? null : _items[i].serviceId,
                                  isDense: true,
                                  decoration: InputDecoration(labelText: context.l10n.pkgServiceLabel),
                                  items: active
                                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _items[i].serviceId = v ?? ''),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: _items[i].sessionCount.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(labelText: context.l10n.pkgSessionsLabel),
                                  onChanged: (v) => setState(
                                    () => _items[i].sessionCount = int.tryParse(v) ?? _items[i].sessionCount,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => setState(() => _items.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: active.isEmpty
                            ? null
                            : () => setState(
                                  () => _items.add(_DraftItem(serviceId: active.first.id, sessionCount: 1)),
                                ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.l10n.pkgAddServiceAction),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing ? context.l10n.commonSaveChanges : context.l10n.pkgAddTitle,
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
