import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/follow_up.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../customers/data/follow_up_repository.dart';
import '../../customers/presentation/customer_providers.dart';

/// Phase 6 (Follow-up / Reminder) business-wide list. Reuses
/// followUpRepositoryProvider (defined once in customer_providers.dart,
/// following the same shared-repository-provider convention as
/// consultationRepositoryProvider/treatmentHistoryRepositoryProvider).
final followUpListFilterProvider = StateProvider.autoDispose<FollowUpListFilter>(
  (ref) => FollowUpListFilter.dueToday,
);

final businessFollowUpsProvider = FutureProvider.autoDispose<List<FollowUp>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final filter = ref.watch(followUpListFilterProvider);
  return ref.watch(followUpRepositoryProvider).listForBusiness(membership.business.id, filter);
});

/// Dashboard Overview tiles (see dashboard_overview_screen.dart). Each
/// count is its own server-side-scoped query via listForBusiness, exactly
/// like the list screen itself -- never a client-side filter over an
/// unscoped fetch.
final followUpsDueTodayCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return 0;
  final rows = await ref
      .watch(followUpRepositoryProvider)
      .listForBusiness(membership.business.id, FollowUpListFilter.dueToday);
  return rows.length;
});

final followUpsOverdueCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return 0;
  final rows = await ref
      .watch(followUpRepositoryProvider)
      .listForBusiness(membership.business.id, FollowUpListFilter.overdue);
  return rows.length;
});
