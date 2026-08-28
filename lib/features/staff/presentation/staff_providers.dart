import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/staff_member.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(supabaseClientProvider));
});

final staffMembersProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(staffRepositoryProvider).listMembers(membership.business.id);
});
