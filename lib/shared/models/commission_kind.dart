import '../../l10n/generated/app_localizations.dart';

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

  String label(AppLocalizations l10n) => switch (this) {
    CommissionKind.percentage => l10n.commissionKindPercentage,
    CommissionKind.fixed => l10n.commissionKindFixed,
  };
}
