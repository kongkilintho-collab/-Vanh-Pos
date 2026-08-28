import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/customer.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(supabaseClientProvider));
});

final customerSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final customersListProvider = FutureProvider.autoDispose<List<Customer>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final query = ref.watch(customerSearchQueryProvider);
  return ref.watch(customerRepositoryProvider).listForBusiness(membership.business.id, query: query);
});

final customerDetailProvider =
    FutureProvider.autoDispose.family<Customer, String>((ref, customerId) async {
  return ref.watch(customerRepositoryProvider).getById(customerId);
});

final customerNotesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  return ref.watch(customerRepositoryProvider).listNotes(customerId);
});

final customerSalesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(customerRepositoryProvider).listSales(membership.business.id, customerId);
});
