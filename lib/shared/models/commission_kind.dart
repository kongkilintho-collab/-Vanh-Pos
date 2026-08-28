/// Mirrors the `commission_kind` enum in supabase/migrations/0001_extensions_and_enums.sql.
enum CommissionKind {
  percentage,
  fixed;

  static CommissionKind fromDb(String value) {
    return CommissionKind.values.firstWhere(
      (k) => k.dbValue == value,
      orElse: () => throw ArgumentError('Unknown commission_kind: $value'),
    );
  }

  String get dbValue => switch (this) {
        CommissionKind.percentage => 'PERCENTAGE',
        CommissionKind.fixed => 'FIXED',
      };

  String get label => switch (this) {
        CommissionKind.percentage => 'Percentage',
        CommissionKind.fixed => 'Fixed amount',
      };
}
