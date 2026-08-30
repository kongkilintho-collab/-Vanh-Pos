import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/audit_log.dart';

/// Read-only audit log access (F9-3). Relies entirely on the existing
/// audit_logs_select RLS policy (ADMIN+, see 0015_rls_policies.sql,
/// untouched by 0026/0027) -- this repository never writes anything;
/// audit_logs_insert has no policy at all as of 0026, so only the
/// SECURITY DEFINER RPCs that produce these rows can create them.
class AuditLogRepository {
  final SupabaseClient _client;

  AuditLogRepository(this._client);

  Future<List<AuditLog>> list(
    String businessId, {
    String? action,
    String? entityType,
    DateTime? from,
    DateTime? to,
  }) async {
    var builder = _client
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .eq('business_id', businessId);
    if (action != null) builder = builder.eq('action', action);
    if (entityType != null) builder = builder.eq('entity_type', entityType);
    if (from != null) builder = builder.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) builder = builder.lte('created_at', to.toUtc().toIso8601String());

    final rows = await builder.order('created_at', ascending: false).limit(100);
    return (rows as List).map((r) => AuditLog.fromJson(r as Map<String, dynamic>)).toList();
  }
}
