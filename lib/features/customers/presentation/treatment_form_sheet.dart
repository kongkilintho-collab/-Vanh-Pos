import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/service.dart';
import '../../../shared/models/staff_member.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../pos/presentation/pos_providers.dart';
import '../../services/presentation/service_providers.dart';
import 'customer_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Phase 4 (Customer Treatment History) manual/walk-in entry -- the
/// customer is fixed from the Customer Detail context the sheet was
/// opened from (never reselected here). Calls create_treatment_record
/// (see supabase/migrations/0047_treatment_history.sql), which resolves
/// and validates every identity field server-side; this sheet never sends
/// a name snapshot.
Future<void> showTreatmentFormSheet(BuildContext context, {required String customerId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TreatmentFormSheet(customerId: customerId),
  );
}

class _TreatmentFormSheet extends ConsumerStatefulWidget {
  final String customerId;

  const _TreatmentFormSheet({required this.customerId});

  @override
  ConsumerState<_TreatmentFormSheet> createState() => _TreatmentFormSheetState();
}

class _TreatmentFormSheetState extends ConsumerState<_TreatmentFormSheet> {
  String? _serviceId;
  String? _staffId;
  DateTime _date = DateTime.now();
  final _notesController = TextEditingController();
  final _resultController = TextEditingController();
  final _feedbackController = TextEditingController();
  final _beforeAfterController = TextEditingController();
  DateTime? _followUpDate;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    _resultController.dispose();
    _feedbackController.dispose();
    _beforeAfterController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  Future<void> _submit() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    if (_serviceId == null) {
      setState(() => _error = context.l10n.treatmentServiceRequired);
      return;
    }
    if (_staffId == null) {
      setState(() => _error = context.l10n.treatmentStaffRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(treatmentHistoryRepositoryProvider).create(
            businessId: businessId,
            customerId: widget.customerId,
            serviceId: _serviceId!,
            staffId: _staffId!,
            treatmentDate: _date,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            result: _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
            customerFeedback:
                _feedbackController.text.trim().isEmpty ? null : _feedbackController.text.trim(),
            beforeAfterReference:
                _beforeAfterController.text.trim().isEmpty ? null : _beforeAfterController.text.trim(),
            followUpDate: _followUpDate,
          );
      ref.invalidate(customerTreatmentHistoryProvider(widget.customerId));
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
    final servicesAsync = ref.watch(servicesListProvider);
    final staffAsync = ref.watch(staffListProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.treatmentFormTitle, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            servicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(friendlyError(err, context.l10n)),
              data: (services) => DropdownButtonFormField<String>(
                initialValue: _serviceId,
                decoration: InputDecoration(labelText: context.l10n.treatmentServiceLabel),
                items: services
                    .map((Service s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _serviceId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            staffAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(friendlyError(err, context.l10n)),
              data: (staff) => DropdownButtonFormField<String>(
                initialValue: _staffId,
                decoration: InputDecoration(labelText: context.l10n.treatmentStaffLabel),
                items: staff
                    .map((StaffMember m) => DropdownMenuItem(value: m.userId, child: Text(m.fullName)))
                    .toList(),
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(context.l10n.treatmentDateLabel),
              subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              trailing: TextButton(onPressed: _pickDate, child: Text(context.l10n.commonChoose)),
            ),
            const Divider(),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: context.l10n.treatmentNotesLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _resultController,
              decoration: InputDecoration(labelText: context.l10n.treatmentResultLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _feedbackController,
              decoration: InputDecoration(labelText: context.l10n.treatmentFeedbackLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _beforeAfterController,
              decoration: InputDecoration(labelText: context.l10n.treatmentBeforeAfterLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: Text(context.l10n.treatmentFollowUpLabel),
              subtitle: Text(
                _followUpDate == null
                    ? '—'
                    : '${_followUpDate!.year}-${_followUpDate!.month.toString().padLeft(2, '0')}-${_followUpDate!.day.toString().padLeft(2, '0')}',
              ),
              trailing: TextButton(onPressed: _pickFollowUpDate, child: Text(context.l10n.commonChoose)),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: context.l10n.treatmentSaveAction,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
