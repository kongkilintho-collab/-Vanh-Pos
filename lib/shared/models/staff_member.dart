import 'business_role.dart';

/// A co-worker in the current business, for staff-assignment pickers and
/// staff management.
class StaffMember {
  final String userId;
  final String fullName;
  final BusinessRole role;
  final bool active;

  const StaffMember({
    required this.userId,
    required this.fullName,
    required this.role,
    this.active = true,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return StaffMember(
      userId: json['user_id'] as String,
      fullName: profile?['full_name'] as String? ?? 'Unknown',
      role: BusinessRole.fromDb(json['role'] as String),
      // Absent (rather than false) in call sites that don't select it, e.g.
      // PosRepository.listStaff(), which only ever fetches active=true rows.
      active: json['active'] as bool? ?? true,
    );
  }
}
