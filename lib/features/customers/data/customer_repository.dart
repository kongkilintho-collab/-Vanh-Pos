import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/customer.dart';

/// CRM-scoped customer data access. Deliberately independent from
/// PosRepository's own search/quick-create (same query technique, not a
/// shared class) so nothing here can ever affect the Day 2 POS checkout
/// flow -- this file never touches pos_repository.dart.
class CustomerRepository {
  final SupabaseClient _client;

  CustomerRepository(this._client);

  Future<List<Customer>> listForBusiness(String businessId, {String query = ''}) async {
    var builder = _client.from('customers').select().eq('business_id', businessId);
    final q = query.trim();
    if (q.isNotEmpty) {
      builder = builder.or('name.ilike.%$q%,phone.ilike.%$q%');
    }
    final rows = await builder.order('name').limit(100);
    return (rows as List).map((r) => Customer.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Customer> getById(String id) async {
    final row = await _client.from('customers').select().eq('id', id).single();
    return Customer.fromJson(row);
  }

  Future<Customer> create(Customer customer) async {
    final row = await _client
        .from('customers')
        .insert(customer.toInsertJson(businessId: customer.businessId))
        .select()
        .single();
    return Customer.fromJson(row);
  }

  Future<Customer> update(Customer customer) async {
    final row = await _client
        .from('customers')
        .update(customer.toInsertJson(businessId: customer.businessId))
        .eq('id', customer.id)
        .select()
        .single();
    return Customer.fromJson(row);
  }

  Future<List<Map<String, dynamic>>> listNotes(String customerId) async {
    final rows = await _client
        .from('customer_notes')
        .select('id, note, created_at, profiles(full_name)')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// customer_notes is append-only by design (see 0015_rls_policies.sql --
  /// there is no UPDATE/DELETE policy on it), so this repository
  /// intentionally exposes no editNote/deleteNote method.
  Future<void> addNote({required String businessId, required String customerId, required String note}) async {
    await _client.from('customer_notes').insert({
      'business_id': businessId,
      'customer_id': customerId,
      'note': note,
    });
  }

  /// Purchase history for a customer's profile view. Rides the existing
  /// sales_select RLS policy (is_member(business_id)) -- no new policy.
  Future<List<Map<String, dynamic>>> listSales(String businessId, String customerId) async {
    final rows = await _client
        .from('sales')
        .select('id, receipt_number, total_amount, status, created_at')
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
