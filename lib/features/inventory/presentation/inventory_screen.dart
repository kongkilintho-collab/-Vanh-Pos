import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/inventory_movement.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../products/presentation/product_providers.dart';
import 'inventory_providers.dart';
import 'stock_adjustment_sheet.dart';
import 'supplier_form_sheet.dart';
import '../../../l10n/l10n_extensions.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: context.l10n.invTabStock),
                Tab(text: context.l10n.invTabMovements),
                Tab(text: context.l10n.invTabSuppliers),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_StockTab(), _MovementsTab(), _SuppliersTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTab extends ConsumerWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsListProvider);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ErrorBanner(message: friendlyError(err, context.l10n)),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warehouse_outlined,
                    size: 40,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l10n.invNoProductsYetTitle,
                    style: AppTextStyles.title,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.invNoProductsYetSubtitle,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final lowStockCount = products.where((p) => p.isLowStock).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lowStockCount > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.invLowStockWarning(lowStockCount),
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                itemCount: products.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _StockTile(product: products[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StockTile extends StatelessWidget {
  final Product product;

  const _StockTile({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: product.isLowStock
              ? AppColors.dangerBg
              : AppColors.primaryLight,
          child: Icon(
            Icons.inventory_2_outlined,
            color: product.isLowStock ? AppColors.danger : AppColors.primary,
            size: 18,
          ),
        ),
        title: Text(product.name, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          context.l10n.invLowStockAlertAt(product.minimumStock),
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.invInStock(product.stockQuantity),
              style: AppTextStyles.bodyStrong.copyWith(
                color: product.isLowStock ? AppColors.danger : null,
              ),
            ),
            IconButton(
              tooltip: context.l10n.invAdjustStockTooltip,
              icon: const Icon(Icons.tune, size: 18),
              onPressed: () =>
                  showStockAdjustmentSheet(context, product: product),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(inventoryMovementsProvider);

    return movementsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ErrorBanner(message: friendlyError(err, context.l10n)),
        ),
      ),
      data: (movements) {
        if (movements.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                context.l10n.invNoMovementsYet,
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: movements.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) =>
              _MovementTile(movement: movements[index]),
        );
      },
    );
  }
}

class _MovementTile extends StatelessWidget {
  final InventoryMovement movement;

  const _MovementTile({required this.movement});

  @override
  Widget build(BuildContext context) {
    final isPositive = movement.quantity > 0;
    return Card(
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        title: Text(
          movement.productName ?? context.l10n.invUnknownProduct,
          style: AppTextStyles.bodyStrong,
        ),
        subtitle: Text(
          [
            movement.movementType.label(context.l10n),
            DateFormat(
              'MMM d, y · h:mm a',
            ).format(movement.createdAt.toLocal()),
            if (movement.note != null && movement.note!.isNotEmpty)
              movement.note!,
          ].join(' · '),
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Text(
          '${isPositive ? '+' : ''}${movement.quantity}',
          style: AppTextStyles.bodyStrong.copyWith(
            color: isPositive ? AppColors.success : AppColors.danger,
          ),
        ),
      ),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSupplierFormSheet(context),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.invAddSupplier),
      ),
      body: suppliersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 40,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.invNoSuppliersYetTitle,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.invNoSuppliersYetSubtitle,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              88,
            ),
            itemCount: suppliers.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _SupplierTile(supplier: suppliers[index]),
          );
        },
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  final Supplier supplier;

  const _SupplierTile({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Text(
            supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(supplier.name, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          supplier.phone ?? supplier.email ?? context.l10n.invNoContactInfo,
          style: AppTextStyles.caption.copyWith(
            color: supplier.active ? AppColors.muted : AppColors.danger,
          ),
        ),
        trailing: supplier.active
            ? null
            : Text(
                context.l10n.invInactive,
                style: AppTextStyles.caption.copyWith(color: AppColors.danger),
              ),
        onTap: () => showSupplierFormSheet(context, existing: supplier),
      ),
    );
  }
}
