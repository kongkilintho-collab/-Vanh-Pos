import 'package:decimal/decimal.dart';

import 'package_item.dart';

class Package {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final Decimal price;
  final int? validityDays;
  final bool active;
  final List<PackageItem> items;

  const Package({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    required this.price,
    this.validityDays,
    required this.active,
    this.items = const [],
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    final rawItems = json['package_items'] as List<dynamic>?;
    return Package(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: Decimal.parse(json['price'].toString()),
      validityDays: json['validity_days'] as int?,
      active: json['active'] as bool? ?? true,
      items: rawItems == null
          ? const []
          : rawItems.map((r) => PackageItem.fromJson(r as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      'name': name,
      if (description != null && description!.isNotEmpty) 'description': description,
      'price': price.toString(),
      if (validityDays != null) 'validity_days': validityDays,
      'active': active,
    };
  }
}
