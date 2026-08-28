import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/inventory_movement_type.dart';
import '../../../shared/models/product.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../products/presentation/product_providers.dart';
import 'inventory_providers.dart';

Future<void> showStockAdjustmentSheet(BuildContext context, {required Product product}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StockAdjustmentSheet(product: product),
  );
}

enum _Direction { add, remove }

class _StockAdjustmentSheet extends ConsumerStatefulWidget {
  final Product product;

  const _StockAdjustmentSheet({required this.product});

  @override
  ConsumerState<_StockAdjustmentSheet> createState() => _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends ConsumerState<_StockAdjustmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  _Direction _direction = _Direction.add;
  InventoryMovementType _movementType = InventoryMovementType.purchase;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    final magnitude = int.parse(_quantityController.text.trim());
    final delta = _direction == _Direction.add ? magnitude : -magnitude;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final branchId = await repo.primaryBranchId(businessId);
      await repo.adjustStock(
        businessId: businessId,
        productId: widget.product.id,
        branchId: branchId,
        movementType: _movementType,
        quantityDelta: delta,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );

      ref.invalidate(productsListProvider);
      ref.invalidate(inventoryMovementsProvider);
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
              Text('Adjust stock', style: AppTextStyles.headline),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${widget.product.name} · currently ${widget.product.stockQuantity} in stock',
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              SegmentedButton<_Direction>(
                segments: const [
                  ButtonSegment(value: _Direction.add, label: Text('Add stock'), icon: Icon(Icons.add)),
                  ButtonSegment(value: _Direction.remove, label: Text('Remove stock'), icon: Icon(Icons.remove)),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (v) {
                  final parsed = int.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed <= 0) return 'Enter a positive whole number';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<InventoryMovementType>(
                initialValue: _movementType,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: InventoryMovementType.manualTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (t) => setState(() => _movementType = t ?? _movementType),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Save adjustment', onPressed: _submit, loading: _loading),
            ],
          ),
        ),
      ),
    );
  }
}
