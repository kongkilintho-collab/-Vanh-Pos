import 'package:decimal/decimal.dart';

import 'commission_kind.dart';

class Service {
  final String id;
  final String businessId;
  final String? categoryId;
  final String name;
  final String? description;
  final Decimal price;
  final int durationMinutes;
  final CommissionKind commissionType;
  final Decimal commissionValue;
  final bool active;

  const Service({
    required this.id,
    required this.businessId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    required this.durationMinutes,
    required this.commissionType,
    required this.commissionValue,
    required this.active,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: Decimal.parse(json['price'].toString()),
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      commissionType: CommissionKind.fromDb(json['commission_type'] as String? ?? 'PERCENTAGE'),
      commissionValue: Decimal.parse((json['commission_value'] ?? 0).toString()),
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      if (categoryId != null) 'category_id': categoryId,
      'name': name,
      if (description != null && description!.isNotEmpty) 'description': description,
      'price': price.toString(),
      'duration_minutes': durationMinutes,
      'commission_type': commissionType.dbValue,
      'commission_value': commissionValue.toString(),
      'active': active,
    };
  }
}
