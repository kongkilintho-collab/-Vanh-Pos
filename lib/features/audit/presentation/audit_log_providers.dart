import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/audit_log.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/widgets/date_range_filter.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/audit_log_repository.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository(ref.watch(supabaseClientProvider));
});

class AuditLogFilter {
  final String? action;
  final String? entityType;
  final DateRangeSelection range;

  const AuditLogFilter({this.action, this.entityType, required this.range});

  AuditLogFilter copyWith({
    String? action,
    bool clearAction = false,
    String? entityType,
    bool clearEntityType = false,
    DateRangeSelection? range,
  }) {
    return AuditLogFilter(
      action: clearAction ? null : (action ?? this.action),
      entityType: clearEntityType ? null : (entityType ?? this.entityType),
      range: range ?? this.range,
    );
  }
}

final auditLogFilterProvider = StateProvider.autoDispose<AuditLogFilter>(
  (ref) => AuditLogFilter(range: DateRangeSelection.thisMonth()),
);

final auditLogListProvider = FutureProvider.autoDispose<List<AuditLog>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final filter = ref.watch(auditLogFilterProvider);
  return ref.watch(auditLogRepositoryProvider).list(
        membership.business.id,
        action: filter.action,
        entityType: filter.entityType,
        from: filter.range.from,
        to: filter.range.to,
      );
});
