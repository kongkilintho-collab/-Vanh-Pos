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
import '../../auth/presentation/business_context_provider.dart';
import '../../customers/presentation/customer_providers.dart';
import '../../customers/presentation/follow_up_form_sheet.dart';
import 'follow_up_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Business-wide Follow-up List detail/actions sheet -- the same status-
/// transition + reschedule shape as _FollowUpCard in
/// customer_detail_screen.dart, but invalidating businessFollowUpsProvider
/// (and the per-customer provider, since the same row is visible from
/// both places) instead of only the per-customer one.
Future<void> showFollowUpDetailSheet(BuildContext context, FollowUp followUp) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FollowUpDetailSheet(followUp: followUp),
  );
}

class _FollowUpDetailSheet extends ConsumerStatefulWidget {
  final FollowUp followUp;

  const _FollowUpDetailSheet({required this.followUp});

  @override
  ConsumerState<_FollowUpDetailSheet> createState() => _FollowUpDetailSheetState();
}

class _FollowUpDetailSheetState extends ConsumerState<_FollowUpDetailSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _changeStatus(FollowUpStatus status) async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(followUpRepositoryProvider).setStatus(
            businessId: businessId,
            followUpId: widget.followUp.id,
            status: status,
          );
      ref.invalidate(businessFollowUpsProvider);
      ref.invalidate(customerFollowUpsProvider(widget.followUp.customerId));
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
    final followUp = widget.followUp;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            followUp.customerName ?? context.l10n.followUpFormTitle,
            style: AppTextStyles.headline,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            DateFormat('MMM d, y · h:mm a').format(followUp.dueDate.toLocal()),
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          _DetailRow(icon: Icons.badge_outlined, label: followUp.assignedStaffNameSnapshot),
          if (followUp.followUpNotes != null && followUp.followUpNotes!.isNotEmpty)
            _DetailRow(icon: Icons.notes_outlined, label: followUp.followUpNotes!),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (followUp.status == FollowUpStatus.pending)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final next in followUp.status.nextOptions)
                  OutlinedButton(
                    onPressed: () => _changeStatus(next),
                    child: Text(next.label(context.l10n)),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showFollowUpFormSheet(
                      context,
                      customerId: followUp.customerId,
                      existing: followUp,
                    );
                    ref.invalidate(businessFollowUpsProvider);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: Text(context.l10n.followUpRescheduleTitle),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}
