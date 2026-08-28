import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/product.dart';

class ProductRepository {
  final SupabaseClient _client;

  ProductRepository(this._client);

  Future<List<Product>> listForBusiness(String businessId) async {
    final rows = await _client
        .from('products')
        .select()
        .eq('business_id', businessId)
        .order('name');
    return (rows as List).map((r) => Product.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Product> create(Product product) async {
    final row = await _client
        .from('products')
        .insert(product.toInsertJson(businessId: product.businessId))
        .select()
        .single();
    return Product.fromJson(row);
  }

  Future<Product> update(Product product) async {
    final row = await _client
        .from('products')
        .update(product.toInsertJson(businessId: product.businessId))
        .eq('id', product.id)
        .select()
        .single();
    return Product.fromJson(row);
  }
}
