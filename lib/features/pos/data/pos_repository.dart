import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/customer.dart';
import '../../../shared/models/staff_member.dart';

class PosRepository {
  final SupabaseClient _client;

  PosRepository(this._client);

  Future<List<Customer>> searchCustomers(String businessId, String query) async {
    var builder = _client.from('customers').select().eq('business_id', businessId).eq('active', true);
    if (query.trim().isNotEmpty) {
      final q = query.trim();
      builder = builder.or('name.ilike.%$q%,phone.ilike.%$q%');
    }
    final rows = await builder.order('name').limit(20);
    return (rows as List).map((r) => Customer.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Customer> quickCreateCustomer({
    required String businessId,
    required String name,
    String? phone,
  }) async {
    final row = await _client
        .from('customers')
        .insert({
          'business_id': businessId,
          'name': name,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        })
        .select()
        .single();
    return Customer.fromJson(row);
  }

  /// Day 2 is single-branch (per the product spec, multi-branch selection
  /// is future work) — this just resolves the business's one branch,
  /// created automatically at onboarding.
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

  Future<List<StaffMember>> listStaff(String businessId) async {
    final rows = await _client
        .from('business_members')
        .select('user_id, role, profiles(full_name)')
        .eq('business_id', businessId)
        .eq('active', true);
    return (rows as List).map((r) => StaffMember.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Calls the complete_sale RPC (see supabase/migrations/0017_pos_checkout.sql).
  /// Returns the raw sale row; the RPC itself is the atomic transaction —
  /// this is a single network call, not a client-orchestrated sequence.
  Future<Map<String, dynamic>> completeSale({
    required String businessId,
    String? branchId,
    String? customerId,
    required List<Map<String, dynamic>> items,
    required String discountAmount,
    required String taxAmount,
    required String paymentMethod,
    required String paidAmount,
    required String idempotencyKey,
  }) async {
    final row = await _client.rpc('complete_sale', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_customer_id': customerId,
      'p_items': items,
      'p_discount_amount': discountAmount,
      'p_tax_amount': taxAmount,
      'p_payment_method': paymentMethod,
      'p_paid_amount': paidAmount,
      'p_idempotency_key': idempotencyKey,
    });
    return row as Map<String, dynamic>;
  }
}
