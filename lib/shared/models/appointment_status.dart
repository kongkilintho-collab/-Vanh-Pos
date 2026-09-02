import '../../l10n/generated/app_localizations.dart';

/// Mirrors the `appointment_status` enum in
/// supabase/migrations/0030_appointments_schema.sql. Valid transitions are
/// enforced server-side by set_appointment_status
/// (0031_appointment_rpcs.sql) -- [nextOptions] here is a UI hint only.
enum AppointmentStatus {
  scheduled,
  confirmed,
  checkedIn,
  completed,
  cancelled,
  noShow;

  static AppointmentStatus fromDb(String value) {
    return AppointmentStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => throw ArgumentError('Unknown appointment_status: $value'),
    );
  }

  String get dbValue => switch (this) {
    AppointmentStatus.scheduled => 'SCHEDULED',
    AppointmentStatus.confirmed => 'CONFIRMED',
    AppointmentStatus.checkedIn => 'CHECKED_IN',
    AppointmentStatus.completed => 'COMPLETED',
    AppointmentStatus.cancelled => 'CANCELLED',
    AppointmentStatus.noShow => 'NO_SHOW',
  };

  String label(AppLocalizations l10n) => switch (this) {
    AppointmentStatus.scheduled => l10n.apptStatusScheduled,
    AppointmentStatus.confirmed => l10n.apptStatusConfirmed,
    AppointmentStatus.checkedIn => l10n.apptStatusCheckedIn,
    AppointmentStatus.completed => l10n.apptStatusCompleted,
    AppointmentStatus.cancelled => l10n.apptStatusCancelled,
    AppointmentStatus.noShow => l10n.apptStatusNoShow,
  };

  bool get isTerminal => switch (this) {
    AppointmentStatus.completed ||
    AppointmentStatus.cancelled ||
    AppointmentStatus.noShow => true,
    _ => false,
  };

  /// Statuses set_appointment_status will accept from this one.
  List<AppointmentStatus> get nextOptions => switch (this) {
    AppointmentStatus.scheduled => const [
      AppointmentStatus.confirmed,
      AppointmentStatus.cancelled,
      AppointmentStatus.noShow,
    ],
    AppointmentStatus.confirmed => const [
      AppointmentStatus.checkedIn,
      AppointmentStatus.cancelled,
      AppointmentStatus.noShow,
    ],
    AppointmentStatus.checkedIn => const [
      AppointmentStatus.completed,
      AppointmentStatus.cancelled,
    ],
    _ => const [],
  };
}
