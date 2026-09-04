import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/follow_up.dart';
import '../../../shared/models/staff_member.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/pos_providers.dart';
import 'customer_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Phase 6 (Follow-up / Reminder) create/reschedule sheet. When [existing]
/// is null this creates a new follow-up (through create_follow_up); when
/// set, this only reschedules due date + assigned staff on that follow-up
/// (through reschedule_follow_up, which only permits PENDING follow-ups --
/// matching treatment_form_sheet/consultation_form_sheet's convention of
/// the customer being fixed by the Customer Detail context the sheet was
/// opened from, never reselected here).
Future<void> showFollowUpFormSheet(
  BuildContext context, {
  required String customerId,
  FollowUp? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FollowUpFormSheet(customerId: customerId, existing: existing),
  );
}

class _FollowUpFormSheet extends ConsumerStatefulWidget {
  final String customerId;
  final FollowUp? existing;

  const _FollowUpFormSheet({required this.customerId, this.existing});

  @override
  ConsumerState<_FollowUpFormSheet> createState() => _FollowUpFormSheetState();
}

class _FollowUpFormSheetState extends ConsumerState<_FollowUpFormSheet> {
  String? _staffId;
  late DateTime _dueDate;
  late TimeOfDay _dueTime;
  final _notesController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _staffId = existing?.assignedStaffId;
    final initialDue = existing?.dueDate.toLocal() ?? DateTime.now().add(const Duration(days: 7));
    _dueDate = DateTime(initialDue.year, initialDue.month, initialDue.day);
    _dueTime = TimeOfDay.fromDateTime(initialDue);
    if (existing != null) {
      _notesController.text = existing.followUpNotes ?? '';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _dueTime);
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _submit() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    if (_staffId == null) {
      setState(() => _error = context.l10n.followUpStaffRequired);
      return;
    }

    final dueDateTime = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
      _dueTime.hour,
      _dueTime.minute,
    );

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(followUpRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          businessId: businessId,
          customerId: widget.customerId,
          assignedStaffId: _staffId!,
          dueDate: dueDateTime,
          followUpNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
      } else {
        await repo.reschedule(
          businessId: businessId,
          followUpId: existing.id,
          dueDate: dueDateTime,
          assignedStaffId: _staffId!,
        );
      }
      ref.invalidate(customerFollowUpsProvider(widget.customerId));
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
    final staffAsync = ref.watch(staffListProvider);
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEditing ? context.l10n.followUpRescheduleTitle : context.l10n.followUpFormTitle,
              style: AppTextStyles.headline,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            staffAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(friendlyError(err, context.l10n)),
              data: (staff) => DropdownButtonFormField<String>(
                initialValue: _staffId,
                decoration: InputDecoration(labelText: context.l10n.followUpStaffLabel),
                items: staff
                    .map((StaffMember m) => DropdownMenuItem(value: m.userId, child: Text(m.fullName)))
                    .toList(),
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      '${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(_dueTime.format(context)),
                  ),
                ),
              ],
            ),
            if (!isEditing) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: context.l10n.followUpNotesLabel),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: isEditing ? context.l10n.followUpRescheduleConfirm : context.l10n.followUpSaveAction,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
