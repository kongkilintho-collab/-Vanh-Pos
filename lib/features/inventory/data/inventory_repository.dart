import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/inventory_movement.dart';
import '../../../shared/models/inventory_movement_type.dart';
import '../../../shared/models/supplier.dart';

/// Inventory (Day 4): the stock-movements ledger, suppliers, and manual
/// stock adjustments. Deliberately independent from ProductRepository (same
/// query technique, not a shared class) so nothing here can affect the
/// Day 2 product catalog -- this file never touches product_repository.dart
/// for writes. Product listing itself is reused as-is from
/// productsListProvider (Day 2) rather than duplicated here; `isLowStock`
/// already exists on the Product model.
class InventoryRepository {
  final SupabaseClient _client;

  InventoryRepository(this._client);

  Future<List<InventoryMovement>> listMovements(String businessId, {String? productId}) async {
    var builder = _client
        .from('inventory_movements')
        .select('*, products(name)')
        .eq('business_id', businessId);
    if (productId != null) builder = builder.eq('product_id', productId);
    final rows = await builder.order('created_at', ascending: false).limit(100);
    return (rows as List).map((r) => InventoryMovement.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Calls the adjust_stock RPC (see
  /// supabase/migrations/0020_inventory_stock_adjustment.sql), which
  /// inserts the inventory_movements row and updates
  /// products.stock_quantity atomically -- this is a single network call,
  /// not a client-orchestrated sequence.
  Future<void> adjustStock({
    required String businessId,
    required String productId,
    String? branchId,
    required InventoryMovementType movementType,
    required int quantityDelta,
    String? note,
  }) async {
    await _client.rpc('adjust_stock', params: {
      'p_business_id': businessId,
      'p_product_id': productId,
      'p_branch_id': branchId,
      'p_movement_type': movementType.dbValue,
      'p_quantity_delta': quantityDelta,
      'p_note': note,
    });
  }

  /// Day 4 is still single-branch (see PosRepository.primaryBranchId's own
  /// note) -- this resolves the business's one branch for the ledger's
  /// branch_id column.
  Future<String?> primaryBranchId(String businessId) async {
    final row = await _client
        .from('branches')
        .select('id')
        .eq('business_id', businessId)
        .eq('active', true)
        .order('created_at')
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<List<Supplier>> listSuppliers(String businessId, {bool activeOnly = false}) async {
    var builder = _client.from('suppliers').select().eq('business_id', businessId);
    if (activeOnly) builder = builder.eq('active', true);
    final rows = await builder.order('name');
    return (rows as List).map((r) => Supplier.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Supplier> createSupplier(Supplier supplier) async {
    final row = await _client
        .from('suppliers')
        .insert(supplier.toInsertJson(businessId: supplier.businessId))
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  Future<Supplier> updateSupplier(Supplier supplier) async {
    final row = await _client
        .from('suppliers')
        .update(supplier.toInsertJson(businessId: supplier.businessId))
        .eq('id', supplier.id)
        .select()
        .single();
    return Supplier.fromJson(row);
  }
}
