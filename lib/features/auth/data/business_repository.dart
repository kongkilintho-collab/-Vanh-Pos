import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/business.dart';
import '../../../shared/models/business_membership.dart';

class BusinessRepository {
  final SupabaseClient _client;

  BusinessRepository(this._client);

  /// The current user's active business memberships, most recently joined
  /// first. Must filter by user_id explicitly: RLS only guarantees the
  /// businesses are ones the caller belongs to, not that a row is the
  /// caller's own — without this filter, any co-member's row in the same
  /// business is also visible and would be returned here.
  Future<List<BusinessMembership>> myMemberships() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('business_members')
        .select('id, role, active, businesses(*)')
        .eq('user_id', userId)
        .eq('active', true)
        .order('created_at');

    return (rows as List)
        .map((row) => BusinessMembership.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Creates a new business with the current user as OWNER, via the
  /// create_business_with_owner() RPC (see 0016_business_onboarding.sql) so
  /// the business + owner membership + default branch are created
  /// atomically instead of as separate, RLS-fragile inserts.
  Future<Business> createBusiness({
    required String name,
    String? phone,
    String? email,
    String? address,
    String currency = 'LAK',
    String timezone = 'Asia/Vientiane',
  }) async {
    final row = await _client.rpc('create_business_with_owner', params: {
      'p_name': name,
      'p_phone': phone,
      'p_email': email,
      'p_address': address,
      'p_currency': currency,
      'p_timezone': timezone,
    });

    return Business.fromJson(row as Map<String, dynamic>);
  }

  /// Calls the update_business_settings RPC (see
  /// supabase/migrations/0028_business_settings_rpc.sql), which atomically
  /// updates the business row and writes a SETTINGS_CHANGE audit_logs row.
  /// This is the only sanctioned write path to businesses -- direct table
  /// UPDATEs are no longer permitted by RLS as of that migration.
  Future<Business> updateSettings({
    required String businessId,
    required String name,
    String? phone,
    String? email,
    String? address,
    required String currency,
    required bool taxEnabled,
    required double taxRate,
    String? logoUrl,
  }) async {
    final row = await _client.rpc('update_business_settings', params: {
      'p_business_id': businessId,
      'p_name': name,
      'p_phone': phone,
      'p_email': email,
      'p_address': address,
      'p_currency': currency,
      'p_tax_enabled': taxEnabled,
      'p_tax_rate': taxRate,
      'p_logo_url': logoUrl,
    });
    return Business.fromJson(row as Map<String, dynamic>);
  }
}
