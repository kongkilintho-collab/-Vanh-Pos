import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/business_role.dart';
import '../../../shared/models/staff_member.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'staff_invite_sheet.dart';
import 'staff_providers.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffMembersProvider);
    final myRole = ref.watch(currentMembershipProvider)?.role;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStaffInviteSheet(context),
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Invite'),
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
        ),
        data: (members) {
          if (members.isEmpty) {
            return Center(
              child: Text('No staff yet.', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 88),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _StaffTile(member: members[index], myRole: myRole ?? BusinessRole.staff),
          );
        },
      ),
    );
  }
}

class _StaffTile extends ConsumerWidget {
  final StaffMember member;
  final BusinessRole myRole;

  const _StaffTile({required this.member, required this.myRole});

  // Purely a UX hint (hide/disable controls that RLS would reject anyway) --
  // never the actual security boundary, which is business_members_update's
  // RLS policy.
  bool get _canEdit {
    if (!myRole.isAtLeast(BusinessRole.admin)) return false;
    if (member.role == BusinessRole.owner && myRole != BusinessRole.owner) return false;
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        leading: CircleAvatar(
          backgroundColor: member.active ? AppColors.primaryLight : AppColors.border,
          child: Text(
            member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?',
            style: TextStyle(color: member.active ? AppColors.primary : AppColors.muted, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(member.fullName, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          member.active ? member.role.label : '${member.role.label} · Inactive',
          style: AppTextStyles.caption.copyWith(color: member.active ? AppColors.muted : AppColors.danger),
        ),
        trailing: _canEdit
            ? IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: () => _showManageSheet(context, ref),
              )
            : null,
      ),
    );
  }

  void _showManageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _ManageMemberSheet(member: member, myRole: myRole),
    );
  }
}

class _ManageMemberSheet extends ConsumerStatefulWidget {
  final StaffMember member;
  final BusinessRole myRole;

  const _ManageMemberSheet({required this.member, required this.myRole});

  @override
  ConsumerState<_ManageMemberSheet> createState() => _ManageMemberSheetState();
}

class _ManageMemberSheetState extends ConsumerState<_ManageMemberSheet> {
  bool _loading = false;
  String? _error;

  List<BusinessRole> get _assignableRoles {
    // Only an OWNER may grant OWNER/ADMIN -- mirrors invite_business_member
    // and the business_members_update RLS policy exactly. Enforced there
    // regardless; this just avoids offering an option that would be
    // rejected.
    if (widget.myRole == BusinessRole.owner) return BusinessRole.values;
    return BusinessRole.values.where((r) => r != BusinessRole.owner && r != BusinessRole.admin).toList();
  }

  Future<void> _changeRole(BusinessRole role) async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).updateRole(
            businessId: businessId,
            userId: widget.member.userId,
            role: role.dbValue,
          );
      ref.invalidate(staffMembersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).setActive(
            businessId: businessId,
            userId: widget.member.userId,
            active: !widget.member.active,
          );
      ref.invalidate(staffMembersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.member.fullName, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: AppSpacing.md)],
            Text('Change role', style: AppTextStyles.captionStrong.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final role in _assignableRoles)
                  ChoiceChip(
                    label: Text(role.label),
                    selected: role == widget.member.role,
                    onSelected: _loading ? null : (_) => _changeRole(role),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _loading ? null : _toggleActive,
              icon: Icon(widget.member.active ? Icons.block_outlined : Icons.check_circle_outline, size: 18),
              label: Text(widget.member.active ? 'Deactivate' : 'Reactivate'),
            ),
          ],
        ),
      ),
    );
  }
}
