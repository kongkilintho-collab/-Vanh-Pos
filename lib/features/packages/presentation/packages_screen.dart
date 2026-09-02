import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/package.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'package_form_sheet.dart';
import 'package_providers.dart';
import '../../../l10n/l10n_extensions.dart';

class PackagesScreen extends ConsumerWidget {
  const PackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(packagesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPackageFormSheet(context),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.pkgAddTitle),
      ),
      body: packagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (packages) {
          if (packages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.card_giftcard_outlined,
                      size: 40,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(context.l10n.pkgEmptyTitle, style: AppTextStyles.title),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.pkgEmptySubtitle,
                      style: AppTextStyles.body.copyWith(color: AppColors.muted),
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
            itemCount: packages.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PackageTile(package: packages[index]),
          );
        },
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final Package package;

  const _PackageTile({required this.package});

  @override
  Widget build(BuildContext context) {
    final itemsSummary = package.items
        .map((i) => '${i.serviceName ?? '?'} ×${i.sessionCount}')
        .join(', ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: const Icon(
            Icons.card_giftcard_outlined,
            color: AppColors.primary,
            size: 18,
          ),
        ),
        title: Text(package.name, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          itemsSummary.isEmpty ? context.l10n.pkgNoServicesYet : itemsSummary,
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatMoney(package.price), style: AppTextStyles.bodyStrong),
            if (!package.active) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  context.l10n.invInactive,
                  style: AppTextStyles.caption.copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ],
        ),
        onTap: () => showPackageFormSheet(context, existing: package),
      ),
    );
  }
}
