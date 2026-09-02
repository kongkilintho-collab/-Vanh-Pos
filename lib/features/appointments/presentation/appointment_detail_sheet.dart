import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/appointment_status.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'appointment_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showAppointmentDetailSheet(
  BuildContext context,
  Appointment appointment,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AppointmentDetailSheet(appointment: appointment),
  );
}

class _AppointmentDetailSheet extends ConsumerStatefulWidget {
  final Appointment appointment;

  const _AppointmentDetailSheet({required this.appointment});

  @override
  ConsumerState<_AppointmentDetailSheet> createState() =>
      _AppointmentDetailSheetState();
}

class _AppointmentDetailSheetState
    extends ConsumerState<_AppointmentDetailSheet> {
  bool _loading = false;
  String? _error;
  bool _rescheduling = false;
  late DateTime _newDate = widget.appointment.startAt;
  late TimeOfDay _newTime = TimeOfDay.fromDateTime(widget.appointment.startAt);

  bool get _canReschedule =>
      widget.appointment.status == AppointmentStatus.scheduled ||
      widget.appointment.status == AppointmentStatus.confirmed;

  Future<void> _pickNewDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _newDate = picked);
  }

  Future<void> _pickNewTime() async {
    final picked = await showTimePicker(context: context, initialTime: _newTime);
    if (picked != null) setState(() => _newTime = picked);
  }

  Future<void> _submitReschedule() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    final appointment = widget.appointment;
    final duration = appointment.endAt.difference(appointment.startAt);
    final newStartAt = DateTime(
      _newDate.year,
      _newDate.month,
      _newDate.day,
      _newTime.hour,
      _newTime.minute,
    );
    final newEndAt = newStartAt.add(duration);

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(appointmentRepositoryProvider).reschedule(
            businessId: businessId,
            appointmentId: appointment.id,
            staffId: appointment.staffId,
            startAt: newStartAt,
            endAt: newEndAt,
          );
      ref.invalidate(appointmentsForRangeProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(AppointmentStatus status) async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    String? reason;
    if (status == AppointmentStatus.cancelled) {
      reason = await _promptCancelReason();
      if (reason == null) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(appointmentRepositoryProvider).setStatus(
            businessId: businessId,
            appointmentId: widget.appointment.id,
            status: status.dbValue,
            cancelReason: reason,
          );
      ref.invalidate(appointmentsForRangeProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _promptCancelReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.apptCancelReasonTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.apptCancelReasonOptionalHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.l10n.apptStatusCancelled),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;
    final timeRange =
        '${_formatTime(appointment.startAt)} - ${_formatTime(appointment.endAt)}';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appointment.customerName ?? context.l10n.apptWalkIn,
            style: AppTextStyles.headline,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            timeRange,
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          _DetailRow(
            icon: Icons.badge_outlined,
            label: appointment.staffName,
          ),
          for (final item in appointment.items) ...[
            _DetailRow(
              icon: Icons.spa_outlined,
              label: '${item.nameSnapshot} (${item.durationMinutes} min, ${formatMoney(item.priceSnapshot)})',
            ),
            if (item.customerPackageItemId != null)
              _DetailRow(
                icon: Icons.card_giftcard_outlined,
                label: item.packageTotalSessions != null
                    ? context.l10n.pkgRedemptionRemaining(
                        item.packageNameSnapshot ?? '',
                        item.packageTotalSessions! - (item.packageUsedSessions ?? 0),
                        item.packageTotalSessions!,
                      )
                    : context.l10n.pkgCoveredByPackage,
              ),
          ],
          if (appointment.notes != null && appointment.notes!.isNotEmpty)
            _DetailRow(icon: Icons.notes_outlined, label: appointment.notes!),
          if (appointment.cancelReason != null &&
              appointment.cancelReason!.isNotEmpty)
            _DetailRow(
              icon: Icons.info_outline,
              label: appointment.cancelReason!,
            ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_rescheduling)
            _RescheduleForm(
              date: _newDate,
              time: _newTime,
              onPickDate: _pickNewDate,
              onPickTime: _pickNewTime,
              onCancel: () => setState(() => _rescheduling = false),
              onConfirm: _submitReschedule,
            )
          else ...[
            if (appointment.status.nextOptions.isNotEmpty || _canReschedule)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final next in appointment.status.nextOptions)
                    OutlinedButton(
                      onPressed: () => _changeStatus(next),
                      child: Text(next.label(context.l10n)),
                    ),
                  if (_canReschedule)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _rescheduling = true),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: Text(context.l10n.apptReschedule),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _RescheduleForm extends StatelessWidget {
  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _RescheduleForm({
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickTime,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(time.format(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: Text(context.l10n.commonCancel),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: context.l10n.apptRescheduleConfirm,
                onPressed: onConfirm,
                expand: false,
              ),
            ),
          ],
        ),
      ],
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

String _formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
