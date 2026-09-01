import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/business_role.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'staff_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showStaffInviteSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _StaffInviteSheet(),
  );
}

class _StaffInviteSheet extends ConsumerStatefulWidget {
  const _StaffInviteSheet();

  @override
  ConsumerState<_StaffInviteSheet> createState() => _StaffInviteSheetState();
}

class _StaffInviteSheetState extends ConsumerState<_StaffInviteSheet> {
  final _emailController = TextEditingController();
  BusinessRole _role = BusinessRole.cashier;

  bool _searching = false;
  bool _inviting = false;
  String? _error;

  // null = not searched yet; '' sentinel unused -- we track search state
  // separately so "searched, found nothing" is distinguishable from
  // "haven't searched yet".
  bool _searched = false;
  String? _foundUserId;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    setState(() {
      _searching = true;
      _error = null;
      _searched = false;
      _foundUserId = null;
    });
    try {
      final userId = await ref
          .read(staffRepositoryProvider)
          .findInvitableUserId(businessId: businessId, email: email);
      if (mounted) {
        setState(() {
          _searched = true;
          _foundUserId = userId;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null || _foundUserId == null) return;

    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      await ref
          .read(staffRepositoryProvider)
          .inviteMember(
            businessId: businessId,
            userId: _foundUserId!,
            role: _role.dbValue,
          );
      ref.invalidate(staffMembersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myRole =
        ref.watch(currentMembershipProvider)?.role ?? BusinessRole.staff;
    final assignableRoles = myRole == BusinessRole.owner
        ? BusinessRole.values
        : BusinessRole.values
              .where((r) => r != BusinessRole.owner && r != BusinessRole.admin)
              .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.staffInviteTitle, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.staffInviteSubtitle,
              style: AppTextStyles.body.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.l10n.authEmailLabel,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  label: context.l10n.staffFind,
                  onPressed: _search,
                  loading: _searching,
                  expand: false,
                ),
              ],
            ),
            if (_searched) ...[
              const SizedBox(height: AppSpacing.lg),
              if (_foundUserId == null)
                Text(
                  context.l10n.staffNoAccountFound,
                  style: AppTextStyles.body.copyWith(color: AppColors.warning),
                )
              else ...[
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      context.l10n.staffAccountFound,
                      style: AppTextStyles.bodyStrong,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<BusinessRole>(
                  initialValue: assignableRoles.contains(_role)
                      ? _role
                      : assignableRoles.first,
                  decoration: InputDecoration(
                    labelText: context.l10n.staffRoleLabel,
                  ),
                  items: assignableRoles
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label(context.l10n)),
                        ),
                      )
                      .toList(),
                  onChanged: (r) => setState(() => _role = r ?? _role),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: context.l10n.staffInviteAction,
                  onPressed: _invite,
                  loading: _inviting,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
