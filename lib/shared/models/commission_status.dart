/// Mirrors the `commission_status` enum in supabase/migrations/0001_extensions_and_enums.sql.
enum CommissionStatus {
  pending,
  approved,
  reversed,
  paid;

  static CommissionStatus fromDb(String value) {
    return CommissionStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => throw ArgumentError('Unknown commission_status: $value'),
    );
  }

  String get dbValue => switch (this) {
        CommissionStatus.pending => 'PENDING',
        CommissionStatus.approved => 'APPROVED',
        CommissionStatus.reversed => 'REVERSED',
        CommissionStatus.paid => 'PAID',
      };

  String get label => switch (this) {
        CommissionStatus.pending => 'Pending',
        CommissionStatus.approved => 'Approved',
        CommissionStatus.reversed => 'Reversed',
        CommissionStatus.paid => 'Paid',
      };

  /// The single valid forward transition in the normal PENDING -> APPROVED
  /// -> PAID flow, or null if there is none (PAID is terminal; REVERSED is
  /// a separate correction path, not part of the forward flow).
  CommissionStatus? get nextInFlow => switch (this) {
        CommissionStatus.pending => CommissionStatus.approved,
        CommissionStatus.approved => CommissionStatus.paid,
        CommissionStatus.paid => null,
        CommissionStatus.reversed => null,
      };
}
