import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/consultation_record.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/treatment_record.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/consultation_repository.dart';
import '../data/customer_repository.dart';
import '../data/treatment_history_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(supabaseClientProvider));
});

final treatmentHistoryRepositoryProvider = Provider<TreatmentHistoryRepository>((ref) {
  return TreatmentHistoryRepository(ref.watch(supabaseClientProvider));
});

/// Phase 4 (Customer Treatment History). Tenant-safety is enforced by RLS
/// (is_member(business_id)) on the treatment_history table itself -- this
/// provider's own business_id scoping is a query optimization, not the
/// security boundary.
final customerTreatmentHistoryProvider =
    FutureProvider.autoDispose.family<List<TreatmentRecord>, String>((ref, customerId) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(treatmentHistoryRepositoryProvider).listForCustomer(membership.business.id, customerId);
});

final consultationRepositoryProvider = Provider<ConsultationRepository>((ref) {
  return ConsultationRepository(ref.watch(supabaseClientProvider));
});

/// Phase 5 (Consultation / Customer Consultation Records). Tenant-safety
/// is enforced by RLS (is_member(business_id)) on the consultations table
/// itself -- this provider's own business_id scoping is a query
/// optimization, not the security boundary.
final customerConsultationsProvider =
    FutureProvider.autoDispose.family<List<ConsultationRecord>, String>((ref, customerId) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(consultationRepositoryProvider).listForCustomer(membership.business.id, customerId);
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
