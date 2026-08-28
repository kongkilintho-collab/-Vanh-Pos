import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/service.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/service_repository.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) {
  return ServiceRepository(ref.watch(supabaseClientProvider));
});

final servicesListProvider = FutureProvider.autoDispose<List<Service>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(serviceRepositoryProvider).listForBusiness(membership.business.id);
});
