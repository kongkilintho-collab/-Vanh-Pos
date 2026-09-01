import '../../l10n/generated/app_localizations.dart';

/// Mirrors the `inventory_movement_type` enum in
/// supabase/migrations/0001_extensions_and_enums.sql. SALE is written only
/// by `complete_sale` (see 0017_pos_checkout.sql) -- never offered as a
/// manual-adjustment choice in the UI, and rejected server-side by
/// `adjust_stock` (0020_inventory_stock_adjustment.sql) if attempted.
enum InventoryMovementType {
  purchase,
  sale,
  return_,
  adjustment,
  damage,
  expired;

  static InventoryMovementType fromDb(String value) {
    return InventoryMovementType.values.firstWhere(
      (t) => t.dbValue == value,
      orElse: () =>
          throw ArgumentError('Unknown inventory_movement_type: $value'),
    );
  }

  String get dbValue => switch (this) {
    InventoryMovementType.purchase => 'PURCHASE',
    InventoryMovementType.sale => 'SALE',
    InventoryMovementType.return_ => 'RETURN',
    InventoryMovementType.adjustment => 'ADJUSTMENT',
    InventoryMovementType.damage => 'DAMAGE',
    InventoryMovementType.expired => 'EXPIRED',
  };

  String label(AppLocalizations l10n) => switch (this) {
    InventoryMovementType.purchase => l10n.movementTypePurchase,
    InventoryMovementType.sale => l10n.movementTypeSale,
    InventoryMovementType.return_ => l10n.movementTypeReturn,
    InventoryMovementType.adjustment => l10n.movementTypeAdjustment,
    InventoryMovementType.damage => l10n.movementTypeDamage,
    InventoryMovementType.expired => l10n.movementTypeExpired,
  };

  /// Movement types a MANAGER+ may record by hand via `adjust_stock`. SALE
  /// is excluded -- it is only ever produced by `complete_sale`.
  static const manualTypes = [
    InventoryMovementType.purchase,
    InventoryMovementType.return_,
    InventoryMovementType.adjustment,
    InventoryMovementType.damage,
    InventoryMovementType.expired,
  ];
}
