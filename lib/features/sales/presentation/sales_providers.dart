import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/payment.dart';
import '../../../shared/models/sale.dart';
import '../../../shared/models/sale_item.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(supabaseClientProvider));
});

final salesSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final salesListProvider = FutureProvider.autoDispose<List<Sale>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final query = ref.watch(salesSearchQueryProvider);
  return ref.watch(salesRepositoryProvider).search(membership.business.id, query);
});

class SaleDetail {
  final Sale sale;
  final List<SaleItem> items;
  final List<Payment> payments;

  const SaleDetail({required this.sale, required this.items, required this.payments});
}

final saleDetailProvider = FutureProvider.autoDispose.family<SaleDetail, String>((ref, saleId) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) throw StateError('No active business membership');
  final repo = ref.watch(salesRepositoryProvider);
  final sale = await repo.getById(membership.business.id, saleId);
  final items = await repo.listItems(membership.business.id, saleId);
  final payments = await repo.listPayments(membership.business.id, saleId);
  return SaleDetail(sale: sale, items: items, payments: payments);
});
