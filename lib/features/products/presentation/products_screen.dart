import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/product.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'product_form_sheet.dart';
import 'product_providers.dart';
import '../../../l10n/l10n_extensions.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProductFormSheet(context),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.productsAddTitle),
      ),
      body: productsAsync.when(
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
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.productsEmptyTitle,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.productsEmptySubtitle,
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
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              88,
            ),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _ProductTile(product: products[index]),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;

  const _ProductTile({required this.product});

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
          [
            if (product.sku != null && product.sku!.isNotEmpty)
              context.l10n.productsSkuPrefix(product.sku!),
            context.l10n.invInStock(product.stockQuantity),
          ].join(' · '),
          style: AppTextStyles.caption.copyWith(
            color: product.isLowStock ? AppColors.danger : AppColors.muted,
          ),
        ),
        trailing: Text(
          formatMoney(product.sellingPrice),
          style: AppTextStyles.bodyStrong,
        ),
        onTap: () => showProductFormSheet(context, existing: product),
      ),
    );
  }
}
