import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/staff_member.dart';

/// Staff management. Every write here goes through a SECURITY DEFINER RPC
/// (invite_business_member, set_member_role, set_member_active -- see
/// 0016_business_onboarding.sql and 0027_audit_log_coverage.sql). Role and
/// active-state changes used to be direct `business_members` UPDATEs;
/// they were moved to RPCs in F9-3 so every change writes a
/// PERMISSION_CHANGE audit_logs row atomically -- business_members_update
/// no longer exists, so a direct client UPDATE can no longer reproduce
/// these changes while skipping the audit trail.
///
/// Deliberately independent from PosRepository.listStaff() (same query
/// technique, not a shared class) so nothing here can affect the Day 2
/// POS staff-assignment dropdown -- this file never touches
/// pos_repository.dart.
class StaffRepository {
  final SupabaseClient _client;

  StaffRepository(this._client);

  /// The full roster, including inactive members (business_members_select
  /// is not filtered by active -- see 0015_rls_policies.sql -- so an
  /// active member can legitimately see who's been deactivated, to be
  /// able to reactivate them).
  Future<List<StaffMember>> listMembers(String businessId) async {
    final rows = await _client
        .from('business_members')
        .select('user_id, role, active, profiles(full_name)')
        .eq('business_id', businessId)
        .order('created_at');
    return (rows as List).map((r) => StaffMember.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Resolves an email to a user_id via find_invitable_user_id (see
  /// 0018_staff_invite_lookup.sql). Returns null if no account exists with
  /// that email. Never queries auth.users directly -- this RPC is the only
  /// sanctioned path.
  Future<String?> findInvitableUserId({required String businessId, required String email}) async {
    final result = await _client.rpc('find_invitable_user_id', params: {
      'p_business_id': businessId,
      'p_email': email,
    });
    return result as String?;
  }

  Future<void> inviteMember({
    required String businessId,
    required String userId,
    required String role,
  }) async {
    await _client.rpc('invite_business_member', params: {
      'p_business_id': businessId,
      'p_user_id': userId,
      'p_role': role,
    });
  }

  /// Calls the set_member_role RPC (0027_audit_log_coverage.sql), which
  /// enforces the same ADMIN+/OWNER-row/escalation rules
  /// business_members_update used to and writes one PERMISSION_CHANGE
  /// audit_logs row atomically with the role change.
  Future<void> updateRole({required String businessId, required String userId, required String role}) async {
    await _client.rpc('set_member_role', params: {
      'p_business_id': businessId,
      'p_target_user_id': userId,
      'p_role': role,
    });
  }

  /// Calls the set_member_active RPC (0027_audit_log_coverage.sql) --
  /// same rationale as [updateRole].
  Future<void> setActive({required String businessId, required String userId, required bool active}) async {
    await _client.rpc('set_member_active', params: {
      'p_business_id': businessId,
      'p_target_user_id': userId,
      'p_active': active,
    });
  }
}
