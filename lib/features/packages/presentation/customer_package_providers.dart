import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/customer_package.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/customer_package_repository.dart';

final customerPackageRepositoryProvider = Provider<CustomerPackageRepository>((ref) {
  return CustomerPackageRepository(ref.watch(supabaseClientProvider));
});

final customerPackagesForCustomerProvider = FutureProvider.autoDispose
    .family<List<CustomerPackage>, String>((ref, customerId) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(customerPackageRepositoryProvider).listForCustomer(
        businessId: membership.business.id,
        customerId: customerId,
      );
});
