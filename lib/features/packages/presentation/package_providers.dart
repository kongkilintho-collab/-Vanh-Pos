import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/package.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/package_repository.dart';

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  return PackageRepository(ref.watch(supabaseClientProvider));
});

final packagesListProvider = FutureProvider.autoDispose<List<Package>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(packageRepositoryProvider).listForBusiness(membership.business.id);
});
