import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/staff_member.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/pos_repository.dart';

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository(ref.watch(supabaseClientProvider));
});

final staffListProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(posRepositoryProvider).listStaff(membership.business.id);
});
