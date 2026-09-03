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

/// Phase 5 (Consultation / Customer Consultation Records) manual entry --
/// the customer is fixed from the Customer Detail context the sheet was
/// opened from (never reselected here), matching
/// treatment_form_sheet.dart's own convention. Calls
/// create_consultation_record (see
/// supabase/migrations/0048_consultations.sql), which resolves and
/// validates every identity field server-side; this sheet never sends a
/// name snapshot. appointment_id is deliberately never supplied here --
/// Customer-Detail-initiated creation is always a walk-in consultation
/// (appointment_id = null); a future appointment-context entry point can
/// pass one through the same repository method without any change here.
Future<void> showConsultationFormSheet(BuildContext context, {required String customerId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ConsultationFormSheet(customerId: customerId),
  );
}

class _ConsultationFormSheet extends ConsumerStatefulWidget {
  final String customerId;

  const _ConsultationFormSheet({required this.customerId});

  @override
  ConsumerState<_ConsultationFormSheet> createState() => _ConsultationFormSheetState();
}

class _ConsultationFormSheetState extends ConsumerState<_ConsultationFormSheet> {
  String? _staffId;
  String? _recommendedServiceId;
  DateTime _date = DateTime.now();
  final _notesController = TextEditingController();
  final _concernsController = TextEditingController();
  final _observationsController = TextEditingController();
  final _considerationsController = TextEditingController();
  final _assessmentController = TextEditingController();
  final _recommendationController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    _concernsController.dispose();
    _observationsController.dispose();
    _considerationsController.dispose();
    _assessmentController.dispose();
    _recommendationController.dispose();
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

  Future<void> _submit() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    if (_staffId == null) {
      setState(() => _error = context.l10n.consultationStaffRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(consultationRepositoryProvider).create(
            businessId: businessId,
            customerId: widget.customerId,
            staffId: _staffId!,
            consultationDate: _date,
            recommendedServiceId: _recommendedServiceId,
            consultationNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            customerConcerns:
                _concernsController.text.trim().isEmpty ? null : _concernsController.text.trim(),
            observations:
                _observationsController.text.trim().isEmpty ? null : _observationsController.text.trim(),
            considerations:
                _considerationsController.text.trim().isEmpty ? null : _considerationsController.text.trim(),
            assessment: _assessmentController.text.trim().isEmpty ? null : _assessmentController.text.trim(),
            recommendationNotes: _recommendationController.text.trim().isEmpty
                ? null
                : _recommendationController.text.trim(),
          );
      ref.invalidate(customerConsultationsProvider(widget.customerId));
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
    final servicesAsync = ref.watch(servicesListProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.consultationFormTitle, style: AppTextStyles.headline),
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
                decoration: InputDecoration(labelText: context.l10n.consultationStaffLabel),
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
              title: Text(context.l10n.consultationDateLabel),
              subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              trailing: TextButton(onPressed: _pickDate, child: Text(context.l10n.commonChoose)),
            ),
            const Divider(),
            servicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(friendlyError(err, context.l10n)),
              data: (services) => DropdownButtonFormField<String?>(
                initialValue: _recommendedServiceId,
                decoration: InputDecoration(labelText: context.l10n.consultationRecommendedServiceLabel),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.l10n.consultationRecommendedServiceNone),
                  ),
                  ...services.map(
                    (Service s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _recommendedServiceId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _concernsController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.consultationConcernsLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _observationsController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.consultationObservationsLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _considerationsController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.consultationConsiderationsLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _assessmentController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.consultationAssessmentLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _recommendationController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.l10n.consultationRecommendationLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: context.l10n.consultationNotesLabel),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: context.l10n.consultationSaveAction,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
