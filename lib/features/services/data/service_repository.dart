import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/service.dart';

class ServiceRepository {
  final SupabaseClient _client;

  ServiceRepository(this._client);

  Future<List<Service>> listForBusiness(String businessId) async {
    final rows = await _client
        .from('services')
        .select()
        .eq('business_id', businessId)
        .order('name');
    return (rows as List).map((r) => Service.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Service> create(Service service) async {
    final row = await _client
        .from('services')
        .insert(service.toInsertJson(businessId: service.businessId))
        .select()
        .single();
    return Service.fromJson(row);
  }

  Future<Service> update(Service service) async {
    final row = await _client
        .from('services')
        .update(service.toInsertJson(businessId: service.businessId))
        .eq('id', service.id)
        .select()
        .single();
    return Service.fromJson(row);
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('services').update({'active': active}).eq('id', id);
  }
}
