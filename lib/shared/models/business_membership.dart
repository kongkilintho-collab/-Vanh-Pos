import 'business.dart';
import 'business_role.dart';

/// A business the current user belongs to, together with their role there.
class BusinessMembership {
  final String id;
  final BusinessRole role;
  final bool active;
  final Business business;

  const BusinessMembership({
    required this.id,
    required this.role,
    required this.active,
    required this.business,
  });

  factory BusinessMembership.fromJson(Map<String, dynamic> json) {
    return BusinessMembership(
      id: json['id'] as String,
      role: BusinessRole.fromDb(json['role'] as String),
      active: json['active'] as bool? ?? true,
      business: Business.fromJson(json['businesses'] as Map<String, dynamic>),
    );
  }
}
