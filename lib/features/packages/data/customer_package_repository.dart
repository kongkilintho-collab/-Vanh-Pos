import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/customer_package.dart';

/// All writes go through purchase_package (SECURITY DEFINER,
/// 0037_package_rpcs.sql) -- customer_packages/customer_package_items have
/// a SELECT-only RLS policy (0032), same pattern as appointments.
class CustomerPackageRepository {
  final SupabaseClient _client;

  CustomerPackageRepository(this._client);

  static const _selectColumns = '*, customer_package_items(*)';

  Future<List<CustomerPackage>> listForCustomer({
    required String businessId,
    required String customerId,
  }) async {
    final rows = await _client
        .from('customer_packages')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('purchased_at', ascending: false);
    return (rows as List)
        .map((r) => CustomerPackage.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<CustomerPackage> purchase({
    required String businessId,
    String? branchId,
    required String customerId,
    required String packageId,
    required String paymentMethod,
    required String paidAmount,
    required String idempotencyKey,
  }) async {
    final row = await _client.rpc('purchase_package', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_customer_id': customerId,
      'p_package_id': packageId,
      'p_discount_amount': 0,
      'p_payment_method': paymentMethod,
      'p_paid_amount': paidAmount,
      'p_idempotency_key': idempotencyKey,
    }) as Map<String, dynamic>;
    return _fetchById(businessId, row['id'] as String);
  }

  Future<CustomerPackage> _fetchById(String businessId, String id) async {
    final row = await _client
        .from('customer_packages')
        .select(_selectColumns)
        .eq('business_id', businessId)
        .eq('id', id)
        .single();
    return CustomerPackage.fromJson(row);
  }
}
