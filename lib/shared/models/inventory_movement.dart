import 'inventory_movement_type.dart';

/// Mirrors the `inventory_movements` table in
/// supabase/migrations/0009_inventory.sql, plus one optional display-only
/// field (productName) populated from the products join in
/// InventoryRepository's select. This table is append-only (no
/// UPDATE/DELETE RLS policy) -- corrections are new rows, not edits.
class InventoryMovement {
  final String id;
  final String businessId;
  final String? branchId;
  final String productId;
  final String? productName;
  final InventoryMovementType movementType;
  final int quantity;
  final String? referenceType;
  final String? referenceId;
  final String? note;
  final DateTime createdAt;

  const InventoryMovement({
    required this.id,
    required this.businessId,
    this.branchId,
    required this.productId,
    this.productName,
    required this.movementType,
    required this.quantity,
    this.referenceType,
    this.referenceId,
    this.note,
    required this.createdAt,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    final product = json['products'] as Map<String, dynamic>?;
    return InventoryMovement(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      productId: json['product_id'] as String,
      productName: product?['name'] as String?,
      movementType: InventoryMovementType.fromDb(json['movement_type'] as String),
      quantity: json['quantity'] as int,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
