import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'service_form_sheet.dart';
import 'service_providers.dart';
import '../../../l10n/l10n_extensions.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showServiceFormSheet(context),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.servicesAddTitle),
      ),
      body: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (services) {
          if (services.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.spa_outlined,
                      size: 40,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.servicesEmptyTitle,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.servicesEmptySubtitle,
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
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _ServiceTile(service: services[index]),
          );
        },
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final Service service;

  const _ServiceTile({required this.service});

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
          child: const Icon(
            Icons.spa_outlined,
            color: AppColors.primary,
            size: 18,
          ),
        ),
        title: Text(service.name, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          context.l10n.servicesDurationCommission(
            service.durationMinutes,
            service.commissionType.label(context.l10n),
            service.commissionValue.toString(),
            service.commissionType.dbValue == 'PERCENTAGE' ? '%' : '',
          ),
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatMoney(service.price), style: AppTextStyles.bodyStrong),
            if (!service.active) ...[
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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ],
        ),
        onTap: () => showServiceFormSheet(context, existing: service),
      ),
    );
  }
}
