import 'package:decimal/decimal.dart';

class Customer {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final Decimal totalSpent;
  final int visitCount;
  final bool active;

  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    required this.totalSpent,
    required this.visitCount,
    required this.active,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      totalSpent: Decimal.parse((json['total_spent'] ?? 0).toString()),
      visitCount: json['visit_count'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
    );
  }
}
