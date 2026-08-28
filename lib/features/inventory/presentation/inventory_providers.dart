import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/inventory_movement.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(supabaseClientProvider));
});

final inventoryMovementsProvider = FutureProvider.autoDispose<List<InventoryMovement>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(inventoryRepositoryProvider).listMovements(membership.business.id);
});

final suppliersListProvider = FutureProvider.autoDispose<List<Supplier>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(inventoryRepositoryProvider).listSuppliers(membership.business.id);
});
