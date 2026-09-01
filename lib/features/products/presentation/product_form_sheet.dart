import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/product.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'product_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showProductFormSheet(BuildContext context, {Product? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProductFormSheet(existing: existing),
  );
}

class _ProductFormSheet extends ConsumerStatefulWidget {
  final Product? existing;

  const _ProductFormSheet({this.existing});

  @override
  ConsumerState<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _skuController = TextEditingController(
    text: widget.existing?.sku ?? '',
  );
  late final _sellingPriceController = TextEditingController(
    text: widget.existing?.sellingPrice.toString() ?? '',
  );
  late final _costPriceController = TextEditingController(
    text: widget.existing?.costPrice.toString() ?? '0',
  );
  late final _stockController = TextEditingController(
    text: (widget.existing?.stockQuantity ?? 0).toString(),
  );
  late final _minStockController = TextEditingController(
    text: (widget.existing?.minimumStock ?? 0).toString(),
  );
  late bool _active = widget.existing?.active ?? true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
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
      final product = Product(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        categoryId: widget.existing?.categoryId,
        supplierId: widget.existing?.supplierId,
        name: _nameController.text.trim(),
        sku: _skuController.text.trim(),
        barcode: widget.existing?.barcode,
        description: widget.existing?.description,
        costPrice: Decimal.parse(_costPriceController.text.trim()),
        sellingPrice: Decimal.parse(_sellingPriceController.text.trim()),
        stockQuantity: int.parse(_stockController.text.trim()),
        minimumStock: int.parse(_minStockController.text.trim()),
        active: _active,
      );

      final repo = ref.read(productRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(product);
      } else {
        await repo.update(product);
      }

      ref.invalidate(productsListProvider);
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
                    ? context.l10n.productsEditTitle
                    : context.l10n.productsAddTitle,
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
                  labelText: context.l10n.productNameLabel,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.commonRequired
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _skuController,
                decoration: InputDecoration(
                  labelText: context.l10n.productSkuOptionalLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.productSellingPriceLak,
                      ),
                      validator: (v) {
                        final parsed = Decimal.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < Decimal.zero)
                          return context.l10n.commonInvalid;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.productCostPriceLak,
                      ),
                      validator: (v) {
                        final parsed = Decimal.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < Decimal.zero)
                          return context.l10n.commonInvalid;
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
                    child: TextFormField(
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.productStockQuantityLabel,
                      ),
                      validator: (v) {
                        final parsed = int.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < 0)
                          return context.l10n.commonInvalid;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _minStockController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.productLowStockAlertAtLabel,
                      ),
                      validator: (v) {
                        final parsed = int.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < 0)
                          return context.l10n.commonInvalid;
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
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing
                    ? context.l10n.commonSaveChanges
                    : context.l10n.productsAddTitle,
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
