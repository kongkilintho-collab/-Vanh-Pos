import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/commission.dart';
import '../../../shared/models/commission_status.dart';

/// Every write here is a direct table update against `commissions`, which
/// is already RLS-protected to ADMIN+ (see commissions_update in
/// 0015_rls_policies.sql) -- no SECURITY DEFINER write path, per the Day 3
/// requirement not to introduce one for commission status changes.
class CommissionRepository {
  final SupabaseClient _client;

  CommissionRepository(this._client);

  Future<List<Commission>> listForBusiness(
    String businessId, {
    String? staffId,
    CommissionStatus? status,
  }) async {
    var builder = _client
        .from('commissions')
        .select('*, profiles(full_name), sales(receipt_number)')
        .eq('business_id', businessId);

    if (staffId != null) {
      builder = builder.eq('staff_id', staffId);
    }
    if (status != null) {
      builder = builder.eq('status', status.dbValue);
    }

    final rows = await builder.order('created_at', ascending: false).limit(200);
    return (rows as List).map((r) => Commission.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> updateStatus({
    required String id,
    required String businessId,
    required CommissionStatus status,
  }) async {
    await _client
        .from('commissions')
        .update({'status': status.dbValue})
        .eq('id', id)
        .eq('business_id', businessId);
  }
}
