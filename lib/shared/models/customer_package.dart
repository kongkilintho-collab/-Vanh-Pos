import 'package:decimal/decimal.dart';

import 'customer_package_item.dart';
import 'customer_package_status.dart';

class CustomerPackage {
  final String id;
  final String businessId;
  final String customerId;
  final String? packageId;
  final String? saleId;
  final String nameSnapshot;
  final Decimal pricePaidSnapshot;
  final DateTime purchasedAt;
  final DateTime? expiresAt;
  final CustomerPackageStatus status;
  final List<CustomerPackageItem> items;

  const CustomerPackage({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.packageId,
    this.saleId,
    required this.nameSnapshot,
    required this.pricePaidSnapshot,
    required this.purchasedAt,
    this.expiresAt,
    required this.status,
    this.items = const [],
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory CustomerPackage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['customer_package_items'] as List<dynamic>?;
    return CustomerPackage(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      customerId: json['customer_id'] as String,
      packageId: json['package_id'] as String?,
      saleId: json['sale_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String,
      pricePaidSnapshot: Decimal.parse((json['price_paid_snapshot'] ?? 0).toString()),
      purchasedAt: DateTime.parse(json['purchased_at'] as String),
      expiresAt: json['expires_at'] == null ? null : DateTime.parse(json['expires_at'] as String),
      status: CustomerPackageStatus.fromDb(json['status'] as String),
      items: rawItems == null
          ? const []
          : rawItems
              .map((r) => CustomerPackageItem.fromJson(r as Map<String, dynamic>))
              .toList(),
    );
  }
}
