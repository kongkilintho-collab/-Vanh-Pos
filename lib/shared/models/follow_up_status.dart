import '../../l10n/generated/app_localizations.dart';

/// Mirrors the `follow_up_status` enum in
/// supabase/migrations/0049_follow_ups_and_line_oa.sql. Valid transitions
/// are enforced server-side by set_follow_up_status -- [nextOptions] here
/// is a UI hint only. DUE/OVERDUE are deliberately NOT members of this
/// enum -- they are never stored, only derived (see FollowUp.isOverdue/
/// isDueToday/isUpcoming in follow_up.dart).
enum FollowUpStatus {
  pending,
  completed,
  missed,
  cancelled;

  static FollowUpStatus fromDb(String value) {
    return FollowUpStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => throw ArgumentError('Unknown follow_up_status: $value'),
    );
  }

  String get dbValue => switch (this) {
    FollowUpStatus.pending => 'PENDING',
    FollowUpStatus.completed => 'COMPLETED',
    FollowUpStatus.missed => 'MISSED',
    FollowUpStatus.cancelled => 'CANCELLED',
  };

  String label(AppLocalizations l10n) => switch (this) {
    FollowUpStatus.pending => l10n.followUpStatusPending,
    FollowUpStatus.completed => l10n.followUpStatusCompleted,
    FollowUpStatus.missed => l10n.followUpStatusMissed,
    FollowUpStatus.cancelled => l10n.followUpStatusCancelled,
  };

  /// Statuses set_follow_up_status will accept from this one.
  List<FollowUpStatus> get nextOptions => switch (this) {
    FollowUpStatus.pending => const [
      FollowUpStatus.completed,
      FollowUpStatus.missed,
      FollowUpStatus.cancelled,
    ],
    _ => const [],
  };
}
