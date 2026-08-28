import 'business_role.dart';

/// A co-worker in the current business, for staff-assignment pickers.
class StaffMember {
  final String userId;
  final String fullName;
  final BusinessRole role;

  const StaffMember({required this.userId, required this.fullName, required this.role});

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return StaffMember(
      userId: json['user_id'] as String,
      fullName: profile?['full_name'] as String? ?? 'Unknown',
      role: BusinessRole.fromDb(json['role'] as String),
    );
  }
}
