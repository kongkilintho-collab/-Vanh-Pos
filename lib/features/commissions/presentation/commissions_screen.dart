import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/business_role.dart';
import '../../../shared/models/commission.dart';
import '../../../shared/models/commission_status.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../staff/presentation/staff_providers.dart';
import 'commission_providers.dart';

class CommissionsScreen extends ConsumerWidget {
  const CommissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionsAsync = ref.watch(commissionsListProvider);
    final staffAsync = ref.watch(staffMembersProvider);
    final filter = ref.watch(commissionFilterProvider);
    final myRole = ref.watch(currentMembershipProvider)?.role ?? BusinessRole.staff;
    final canManage = myRole.isAtLeast(BusinessRole.admin);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: filter.staffId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Staff'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All staff')),
                      for (final s in staffAsync.valueOrNull ?? const [])
                        DropdownMenuItem(value: s.userId, child: Text(s.fullName)),
                    ],
                    onChanged: (v) => ref.read(commissionFilterProvider.notifier).state =
                        filter.copyWith(staffId: v, clearStaff: v == null),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<CommissionStatus?>(
                    initialValue: filter.status,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All statuses')),
                      for (final s in CommissionStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) => ref.read(commissionFilterProvider.notifier).state =
                        filter.copyWith(status: v, clearStatus: v == null),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: commissionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
              ),
              data: (commissions) {
                if (commissions.isEmpty) {
                  return Center(
                    child: Text('No commissions found.', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  itemCount: commissions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) =>
                      _CommissionTile(commission: commissions[index], canManage: canManage),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionTile extends ConsumerWidget {
  final Commission commission;
  final bool canManage;

  const _CommissionTile({required this.commission, required this.canManage});

  Color _statusColor() => switch (commission.status) {
        CommissionStatus.pending => AppColors.warning,
        CommissionStatus.approved => AppColors.info,
        CommissionStatus.paid => AppColors.success,
        CommissionStatus.reversed => AppColors.danger,
      };

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, CommissionStatus status) async {
    try {
      await ref.read(commissionRepositoryProvider).updateStatus(
            id: commission.id,
            businessId: commission.businessId,
            status: status,
          );
      ref.invalidate(commissionsListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = commission.status.nextInFlow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(commission.staffName ?? 'Unknown staff', style: AppTextStyles.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (commission.saleReceiptNumber != null) commission.saleReceiptNumber!,
                      DateFormat('MMM d, y').format(commission.createdAt.toLocal()),
                    ].join(' · '),
                    style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatMoney(commission.commissionAmount), style: AppTextStyles.bodyStrong),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(commission.status.label, style: AppTextStyles.caption.copyWith(color: _statusColor())),
                ),
              ],
            ),
            if (canManage && next != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Mark ${next.label}',
                icon: const Icon(Icons.arrow_circle_right_outlined, size: 20),
                onPressed: () => _updateStatus(context, ref, next),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
