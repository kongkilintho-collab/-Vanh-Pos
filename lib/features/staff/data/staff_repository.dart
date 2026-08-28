import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/staff_member.dart';

/// Staff management. Every write here goes through either the existing
/// invite_business_member RPC or a direct business_members update/select --
/// both already RLS/escalation-guard protected (0015_rls_policies.sql,
/// 0016_business_onboarding.sql). This class introduces no new RPC and no
/// new write path; find_invitable_user_id (0018/0019) is the only new
/// backend object it calls, and it is a lookup, not a write.
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

  /// Direct table update -- business_members_update RLS already enforces
  /// ADMIN+ and the OWNER-row/escalation guards (see 0015_rls_policies.sql).
  Future<void> updateRole({required String businessId, required String userId, required String role}) async {
    await _client
        .from('business_members')
        .update({'role': role})
        .eq('business_id', businessId)
        .eq('user_id', userId);
  }

  Future<void> setActive({required String businessId, required String userId, required bool active}) async {
    await _client
        .from('business_members')
        .update({'active': active})
        .eq('business_id', businessId)
        .eq('user_id', userId);
  }
}
