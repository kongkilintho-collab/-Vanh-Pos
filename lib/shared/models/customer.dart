import 'package:decimal/decimal.dart';

class Customer {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? gender;
  final DateTime? birthday;
  final String? notes;
  final Decimal totalSpent;
  final int visitCount;
  final DateTime? lastVisitAt;
  final bool active;

  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.gender,
    this.birthday,
    this.notes,
    required this.totalSpent,
    required this.visitCount,
    this.lastVisitAt,
    required this.active,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      gender: json['gender'] as String?,
      birthday: json['birthday'] == null ? null : DateTime.parse(json['birthday'] as String),
      notes: json['notes'] as String?,
      totalSpent: Decimal.parse((json['total_spent'] ?? 0).toString()),
      visitCount: json['visit_count'] as int? ?? 0,
      lastVisitAt: json['last_visit_at'] == null ? null : DateTime.parse(json['last_visit_at'] as String),
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      'name': name,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      if (gender != null) 'gender': gender,
      if (birthday != null) 'birthday': birthday!.toIso8601String().split('T').first,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}
