import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/follow_up.dart';
import '../../../shared/models/follow_up_status.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../customers/data/follow_up_repository.dart';
import 'follow_up_detail_sheet.dart';
import 'follow_up_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Phase 6 (Follow-up / Reminder) business-wide list. Filters are always
/// server-side-scoped queries (see FollowUpRepository.listForBusiness),
/// never a client-side filter applied to an unscoped fetch.
class FollowUpsScreen extends ConsumerWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(followUpListFilterProvider);
    final followUpsAsync = ref.watch(businessFollowUpsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in FollowUpListFilter.values) ...[
                  ChoiceChip(
                    label: Text(_filterLabel(context, f)),
                    selected: filter == f,
                    onSelected: (_) => ref.read(followUpListFilterProvider.notifier).state = f,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: followUpsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ErrorBanner(message: friendlyError(err, context.l10n)),
              ),
            ),
            data: (followUps) {
              if (followUps.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.followUpListEmpty,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: followUps.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => _FollowUpListTile(followUp: followUps[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  String _filterLabel(BuildContext context, FollowUpListFilter filter) => switch (filter) {
    FollowUpListFilter.dueToday => context.l10n.followUpFilterDueToday,
    FollowUpListFilter.overdue => context.l10n.followUpFilterOverdue,
    FollowUpListFilter.upcoming => context.l10n.followUpFilterUpcoming,
    FollowUpListFilter.completed => context.l10n.followUpFilterCompleted,
  };
}

class _FollowUpListTile extends StatelessWidget {
  final FollowUp followUp;

  const _FollowUpListTile({required this.followUp});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          followUp.customerName ?? context.l10n.followUpFormTitle,
          style: AppTextStyles.bodyStrong,
        ),
        subtitle: Text(
          '${followUp.assignedStaffNameSnapshot} · ${DateFormat('MMM d, y · h:mm a').format(followUp.dueDate.toLocal())}',
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusChip(followUp: followUp),
        onTap: () => showFollowUpDetailSheet(context, followUp),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final FollowUp followUp;

  const _StatusChip({required this.followUp});

  @override
  Widget build(BuildContext context) {
    final label = followUp.isOverdue
        ? context.l10n.followUpOverdueLabel
        : followUp.status.label(context.l10n);
    final color = switch (followUp.status) {
      _ when followUp.isOverdue => AppColors.danger,
      FollowUpStatus.pending => AppColors.primary,
      FollowUpStatus.completed => AppColors.success,
      FollowUpStatus.missed => AppColors.warning,
      FollowUpStatus.cancelled => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: color)),
    );
  }
}
