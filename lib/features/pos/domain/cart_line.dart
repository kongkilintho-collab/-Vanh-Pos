import 'package:decimal/decimal.dart';

import '../../../shared/models/commission_kind.dart';
import '../../../shared/models/sale_item_kind.dart';

/// One line in the in-progress cart. Not persisted until checkout.
class CartLine {
  final String key;
  final SaleItemKind kind;
  final String refId;
  final String name;
  final Decimal unitPrice;
  final int quantity;
  final String? staffId;
  final String? staffName;
  final CommissionKind? commissionType;
  final Decimal? commissionValue;

  /// Only meaningful for products — the stock level as of when it was
  /// added, used for a client-side sanity check. The server re-checks
  /// authoritatively at checkout regardless.
  final int? availableStock;

  const CartLine({
    required this.key,
    required this.kind,
    required this.refId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.staffId,
    this.staffName,
    this.commissionType,
    this.commissionValue,
    this.availableStock,
  });

  Decimal get subtotal => unitPrice * Decimal.fromInt(quantity);

  CartLine copyWith({int? quantity, String? staffId, String? staffName}) {
    return CartLine(
      key: key,
      kind: kind,
      refId: refId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
      commissionType: commissionType,
      commissionValue: commissionValue,
      availableStock: availableStock,
    );
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'item_type': kind.dbValue,
      'service_id': kind == SaleItemKind.service ? refId : null,
      'product_id': kind == SaleItemKind.product ? refId : null,
      'staff_id': staffId,
      'name_snapshot': name,
      'quantity': quantity,
      'unit_price': unitPrice.toString(),
      'discount_amount': '0',
    };
  }
}
