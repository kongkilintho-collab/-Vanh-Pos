import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/sale_item_kind.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../packages/presentation/package_providers.dart';
import '../../packages/presentation/package_purchase_sheet.dart';
import '../../products/presentation/product_providers.dart';
import '../../services/presentation/service_providers.dart';
import '../domain/cart_line.dart';
import 'cart_controller.dart';
import '../../../l10n/l10n_extensions.dart';

const _uuid = Uuid();

enum _ItemTab { services, products, packages }

class ItemPicker extends ConsumerStatefulWidget {
  const ItemPicker({super.key});

  @override
  ConsumerState<ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends ConsumerState<ItemPicker> {
  _ItemTab _tab = _ItemTab.services;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: context.l10n.posSearchServicesOrProducts,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SegmentedButton<_ItemTab>(
            segments: [
              ButtonSegment(
                value: _ItemTab.services,
                label: Text(context.l10n.posServicesTab),
                icon: const Icon(Icons.spa_outlined),
              ),
              ButtonSegment(
                value: _ItemTab.products,
                label: Text(context.l10n.posProductsTab),
                icon: const Icon(Icons.inventory_2_outlined),
              ),
              ButtonSegment(
                value: _ItemTab.packages,
                label: Text(context.l10n.pkgTab),
                icon: const Icon(Icons.card_giftcard_outlined),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: switch (_tab) {
            _ItemTab.services => _ServicesGrid(query: _query),
            _ItemTab.products => _ProductsGrid(query: _query),
            _ItemTab.packages => _PackagesGrid(query: _query),
          },
        ),
      ],
    );
  }
}

class _ServicesGrid extends ConsumerWidget {
  final String query;

  const _ServicesGrid({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesListProvider);
    return servicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          Center(child: ErrorBanner(message: friendlyError(err, context.l10n))),
      data: (services) {
        final filtered = services
            .where((s) => s.active)
            .where((s) => query.isEmpty || s.name.toLowerCase().contains(query))
            .toList();
        if (filtered.isEmpty) {
          return _EmptyPickerState(
            message: services.isEmpty
                ? context.l10n.posNoServicesYet
                : context.l10n.posNoMatches,
          );
        }
        return _ItemGrid(
          count: filtered.length,
          itemBuilder: (i) {
            final s = filtered[i];
            return _ItemCard(
              title: s.name,
              subtitle: formatMoney(s.price),
              icon: Icons.spa_outlined,
              onTap: () => ref
                  .read(cartControllerProvider.notifier)
                  .addLine(
                    CartLine(
                      key: _uuid.v4(),
                      kind: SaleItemKind.service,
                      refId: s.id,
                      name: s.name,
                      unitPrice: s.price,
                      quantity: 1,
                    ),
                  ),
            );
          },
        );
      },
    );
  }
}

class _ProductsGrid extends ConsumerWidget {
  final String query;

  const _ProductsGrid({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsListProvider);
    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          Center(child: ErrorBanner(message: friendlyError(err, context.l10n))),
      data: (products) {
        final filtered = products
            .where((p) => p.active)
            .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
            .toList();
        if (filtered.isEmpty) {
          return _EmptyPickerState(
            message: products.isEmpty
                ? context.l10n.posNoProductsYet
                : context.l10n.posNoMatches,
          );
        }
        return _ItemGrid(
          count: filtered.length,
          itemBuilder: (i) {
            final p = filtered[i];
            final outOfStock = p.stockQuantity <= 0;
            return _ItemCard(
              title: p.name,
              subtitle: outOfStock
                  ? context.l10n.posOutOfStock
                  : context.l10n.posItemsLeft(
                      formatMoney(p.sellingPrice),
                      p.stockQuantity,
                    ),
              subtitleColor: outOfStock ? AppColors.danger : null,
              icon: Icons.inventory_2_outlined,
              disabled: outOfStock,
              onTap: outOfStock
                  ? null
                  : () => ref
                        .read(cartControllerProvider.notifier)
                        .addLine(
                          CartLine(
                            key: _uuid.v4(),
                            kind: SaleItemKind.product,
                            refId: p.id,
                            name: p.name,
                            unitPrice: p.sellingPrice,
                            quantity: 1,
                            availableStock: p.stockQuantity,
                          ),
                        ),
            );
          },
        );
      },
    );
  }
}

class _PackagesGrid extends ConsumerWidget {
  final String query;

  const _PackagesGrid({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(packagesListProvider);
    return packagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          Center(child: ErrorBanner(message: friendlyError(err, context.l10n))),
      data: (packages) {
        final filtered = packages
            .where((p) => p.active)
            .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
            .toList();
        if (filtered.isEmpty) {
          return _EmptyPickerState(
            message: packages.isEmpty ? context.l10n.pkgEmptyTitle : context.l10n.posNoMatches,
          );
        }
        return _ItemGrid(
          count: filtered.length,
          itemBuilder: (i) {
            final p = filtered[i];
            return _ItemCard(
              title: p.name,
              subtitle: formatMoney(p.price),
              icon: Icons.card_giftcard_outlined,
              onTap: () => showPackagePurchaseSheet(context, p),
            );
          },
        );
      },
    );
  }
}

class _ItemGrid extends StatelessWidget {
  final int count;
  final Widget Function(int index) itemBuilder;

  const _ItemGrid({required this.count, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.5,
      ),
      itemCount: count,
      itemBuilder: (context, i) => itemBuilder(i),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final IconData icon;
  final bool disabled;
  final VoidCallback? onTap;

  const _ItemCard({
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.icon,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: subtitleColor ?? AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPickerState extends StatelessWidget {
  final String message;

  const _EmptyPickerState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.muted),
      ),
    );
  }
}
