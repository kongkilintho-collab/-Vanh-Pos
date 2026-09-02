import '../../l10n/generated/app_localizations.dart';

/// Mirrors the `customer_package_status` enum in
/// supabase/migrations/0032_packages_schema.sql.
enum CustomerPackageStatus {
  active,
  expired,
  cancelled;

  static CustomerPackageStatus fromDb(String value) {
    return CustomerPackageStatus.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => throw ArgumentError('Unknown customer_package_status: $value'),
    );
  }

  String get dbValue => switch (this) {
    CustomerPackageStatus.active => 'ACTIVE',
    CustomerPackageStatus.expired => 'EXPIRED',
    CustomerPackageStatus.cancelled => 'CANCELLED',
  };

  String label(AppLocalizations l10n) => switch (this) {
    CustomerPackageStatus.active => l10n.pkgStatusActive,
    CustomerPackageStatus.expired => l10n.pkgStatusExpired,
    CustomerPackageStatus.cancelled => l10n.pkgStatusCancelled,
  };
}
