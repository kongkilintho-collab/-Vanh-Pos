import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/business.dart';
import '../../../shared/models/business_membership.dart';

class BusinessRepository {
  final SupabaseClient _client;

  BusinessRepository(this._client);

  /// The current user's active business memberships, most recently joined
  /// first. RLS guarantees this can never include another user's rows.
  Future<List<BusinessMembership>> myMemberships() async {
    final rows = await _client
        .from('business_members')
        .select('id, role, active, businesses(*)')
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
}
