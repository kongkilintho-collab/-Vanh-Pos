import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/commission.dart';
import '../../../shared/models/commission_status.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/commission_repository.dart';

final commissionRepositoryProvider = Provider<CommissionRepository>((ref) {
  return CommissionRepository(ref.watch(supabaseClientProvider));
});

class CommissionFilter {
  final String? staffId;
  final CommissionStatus? status;

  const CommissionFilter({this.staffId, this.status});

  CommissionFilter copyWith({String? staffId, bool clearStaff = false, CommissionStatus? status, bool clearStatus = false}) {
    return CommissionFilter(
      staffId: clearStaff ? null : (staffId ?? this.staffId),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}

final commissionFilterProvider = StateProvider.autoDispose<CommissionFilter>((ref) => const CommissionFilter());

final commissionsListProvider = FutureProvider.autoDispose<List<Commission>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final filter = ref.watch(commissionFilterProvider);
  return ref.watch(commissionRepositoryProvider).listForBusiness(
        membership.business.id,
        staffId: filter.staffId,
        status: filter.status,
      );
});
