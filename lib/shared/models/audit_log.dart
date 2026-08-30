/// Mirrors the `audit_logs` table in supabase/migrations/0013_audit_logs.sql,
/// plus one optional display-only field (actorName) populated from the
/// profiles join in AuditLogRepository's select.
class AuditLog {
  final String id;
  final String businessId;
  final String? userId;
  final String? actorName;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AuditLog({
    required this.id,
    required this.businessId,
    this.userId,
    this.actorName,
    required this.action,
    required this.entityType,
    this.entityId,
    this.oldData,
    this.newData,
    this.metadata,
    required this.createdAt,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return AuditLog(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      userId: json['user_id'] as String?,
      actorName: profile?['full_name'] as String?,
      action: json['action'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String?,
      oldData: json['old_data'] as Map<String, dynamic>?,
      newData: json['new_data'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
