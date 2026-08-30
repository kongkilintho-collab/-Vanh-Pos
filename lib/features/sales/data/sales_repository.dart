import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/sale.dart';
import '../../../shared/models/sale_item.dart';

/// Read-only sale lookup for the Sales list/detail screens (F9-2). Every
/// query here is a plain SELECT scoped by business_id, same technique as
/// ReportsRepository -- the actual void mutation lives in PosRepository
/// (it calls void_sale, the same RPC-owning repository that already owns
/// completeSale) so this repository never writes anything.
class SalesRepository {
  final SupabaseClient _client;

  SalesRepository(this._client);

  Future<List<Sale>> search(String businessId, String query) async {
    var builder = _client.from('sales').select().eq('business_id', businessId);
    final q = query.trim();
    if (q.isNotEmpty) {
      builder = builder.ilike('receipt_number', '%$q%');
    }
    final rows = await builder.order('created_at', ascending: false).limit(50);
    return (rows as List).map((r) => Sale.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Sale> getById(String businessId, String saleId) async {
    final row = await _client
        .from('sales')
        .select()
        .eq('id', saleId)
        .eq('business_id', businessId)
        .single();
    return Sale.fromJson(row);
  }

  Future<List<SaleItem>> listItems(String businessId, String saleId) async {
    final rows = await _client
        .from('sale_items')
        .select()
        .eq('sale_id', saleId)
        .eq('business_id', businessId)
        .order('created_at');
    return (rows as List).map((r) => SaleItem.fromJson(r as Map<String, dynamic>)).toList();
  }
}
