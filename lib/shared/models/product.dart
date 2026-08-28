import 'package:decimal/decimal.dart';

class Product {
  final String id;
  final String businessId;
  final String? categoryId;
  final String? supplierId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final Decimal costPrice;
  final Decimal sellingPrice;
  final int stockQuantity;
  final int minimumStock;
  final bool active;

  const Product({
    required this.id,
    required this.businessId,
    this.categoryId,
    this.supplierId,
    required this.name,
    this.sku,
    this.barcode,
    this.description,
    required this.costPrice,
    required this.sellingPrice,
    required this.stockQuantity,
    required this.minimumStock,
    required this.active,
  });

  bool get isLowStock => stockQuantity <= minimumStock;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      categoryId: json['category_id'] as String?,
      supplierId: json['supplier_id'] as String?,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      description: json['description'] as String?,
      costPrice: Decimal.parse((json['cost_price'] ?? 0).toString()),
      sellingPrice: Decimal.parse(json['selling_price'].toString()),
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minimumStock: json['minimum_stock'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      if (categoryId != null) 'category_id': categoryId,
      if (supplierId != null) 'supplier_id': supplierId,
      'name': name,
      if (sku != null && sku!.isNotEmpty) 'sku': sku,
      if (barcode != null && barcode!.isNotEmpty) 'barcode': barcode,
      if (description != null && description!.isNotEmpty) 'description': description,
      'cost_price': costPrice.toString(),
      'selling_price': sellingPrice.toString(),
      'stock_quantity': stockQuantity,
      'minimum_stock': minimumStock,
      'active': active,
    };
  }
}
