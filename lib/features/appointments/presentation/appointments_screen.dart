import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/appointment.dart';
import '../../../shared/models/appointment_status.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'appointment_detail_sheet.dart';
import 'appointment_form_sheet.dart';
import 'appointment_providers.dart';
import '../../../l10n/l10n_extensions.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() =>
      _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = _dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    final range = AppointmentRange(monthStart, monthEnd);
    final appointmentsAsync = ref.watch(appointmentsForRangeProvider(range));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showAppointmentFormSheet(context, initialDate: _selectedDay),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.apptBookTitle),
      ),
      body: appointmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (appointments) {
          final byDay = <DateTime, List<Appointment>>{};
          for (final a in appointments) {
            final key = _dateOnly(a.startAt);
            byDay.putIfAbsent(key, () => []).add(a);
          }
          final selected = byDay[_selectedDay] ?? const <Appointment>[];

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(AppSpacing.lg),
                child: TableCalendar<Appointment>(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  calendarFormat: _format,
                  selectedDayPredicate: (d) => _dateOnly(d) == _selectedDay,
                  eventLoader: (d) => byDay[_dateOnly(d)] ?? const [],
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = _dateOnly(selectedDay);
                      _focusedDay = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    setState(() => _focusedDay = focusedDay);
                  },
                  onFormatChanged: (format) {
                    setState(() => _format = format);
                  },
                  availableCalendarFormats: {
                    CalendarFormat.month: context.l10n.apptCalendarMonth,
                    CalendarFormat.week: context.l10n.apptCalendarWeek,
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: selected.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.apptNoAppointmentsThisDay,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          88,
                        ),
                        itemCount: selected.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) =>
                            _AppointmentTile(appointment: selected[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final Appointment appointment;

  const _AppointmentTile({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')}';
    final serviceNames = appointment.items.map((i) => i.nameSnapshot).join(', ');

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Text(timeLabel, style: AppTextStyles.caption),
        ),
        title: Text(
          appointment.customerName ?? context.l10n.apptWalkIn,
          style: AppTextStyles.bodyStrong,
        ),
        subtitle: Text(
          '${appointment.staffName} · $serviceNames',
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusChip(status: appointment.status),
        onTap: () => showAppointmentDetailSheet(context, appointment),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AppointmentStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AppointmentStatus.scheduled => AppColors.muted,
      AppointmentStatus.confirmed => AppColors.primary,
      AppointmentStatus.checkedIn => AppColors.primary,
      AppointmentStatus.completed => AppColors.success,
      AppointmentStatus.cancelled => AppColors.warning,
      AppointmentStatus.noShow => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.label(context.l10n),
        style: AppTextStyles.caption.copyWith(color: color),
      ),
    );
  }
}
