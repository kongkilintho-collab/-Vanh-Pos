import 'package:decimal/decimal.dart';

/// Mirrors the `sale_items` table in supabase/migrations/0007_sales.sql.
/// item_type/product_id/service_id are kept as raw fields (not resolved to
/// a display name via a join) -- name_snapshot is already the authoritative
/// display text captured at sale time, matching how ReceiptSheet uses it.
class SaleItem {
  final String id;
  final String saleId;
  final String itemType;
  final String? serviceId;
  final String? productId;
  final String? staffId;
  final String nameSnapshot;
  final int quantity;
  final Decimal unitPrice;
  final Decimal discountAmount;
  final Decimal subtotal;
  final Decimal commissionAmount;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.itemType,
    this.serviceId,
    this.productId,
    this.staffId,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
    required this.subtotal,
    required this.commissionAmount,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      itemType: json['item_type'] as String,
      serviceId: json['service_id'] as String?,
      productId: json['product_id'] as String?,
      staffId: json['staff_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String,
      quantity: json['quantity'] as int,
      unitPrice: Decimal.parse(json['unit_price'].toString()),
      discountAmount: Decimal.parse((json['discount_amount'] ?? 0).toString()),
      subtotal: Decimal.parse(json['subtotal'].toString()),
      commissionAmount: Decimal.parse((json['commission_amount'] ?? 0).toString()),
    );
  }
}
