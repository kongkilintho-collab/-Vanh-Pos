import '../../l10n/generated/app_localizations.dart';

/// Mirrors the `business_role` enum in supabase/migrations/0001_extensions_and_enums.sql.
enum BusinessRole {
  owner,
  admin,
  manager,
  cashier,
  staff;

  static BusinessRole fromDb(String value) {
    return BusinessRole.values.firstWhere(
      (r) => r.dbValue == value,
      orElse: () => throw ArgumentError('Unknown business_role: $value'),
    );
  }

  String get dbValue => switch (this) {
    BusinessRole.owner => 'OWNER',
    BusinessRole.admin => 'ADMIN',
    BusinessRole.manager => 'MANAGER',
    BusinessRole.cashier => 'CASHIER',
    BusinessRole.staff => 'STAFF',
  };

  String label(AppLocalizations l10n) => switch (this) {
    BusinessRole.owner => l10n.roleOwner,
    BusinessRole.admin => l10n.roleAdmin,
    BusinessRole.manager => l10n.roleManager,
    BusinessRole.cashier => l10n.roleCashier,
    BusinessRole.staff => l10n.roleStaff,
  };

  int get rank => switch (this) {
    BusinessRole.owner => 5,
    BusinessRole.admin => 4,
    BusinessRole.manager => 3,
    BusinessRole.cashier => 2,
    BusinessRole.staff => 1,
  };

  bool isAtLeast(BusinessRole min) => rank >= min.rank;
}
