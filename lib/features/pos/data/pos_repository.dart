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

  /// Calls the complete_sale RPC (see supabase/migrations/0017_pos_checkout.sql,
  /// extended by supabase/migrations/0043_complete_sale_partial_payment.sql).
  /// Returns the raw sale row; the RPC itself is the atomic transaction —
  /// this is a single network call, not a client-orchestrated sequence.
  ///
  /// allowPartialPayment defaults to false and, when false, is not even
  /// included in the request body -- the normal POS checkout path (this
  /// default) sends byte-for-byte the same params it always has, so
  /// existing behavior is completely unchanged. Only the explicit deposit
  /// flow (see deposit_checkout_sheet.dart) ever passes true. The server
  /// remains the sole authority either way: it still independently rejects
  /// zero/negative amounts and an underpayment when this flag is false or
  /// absent (see 0043's own guard), regardless of what the client sends.
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
    bool allowPartialPayment = false,
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
      if (allowPartialPayment) 'p_allow_partial_payment': allowPartialPayment,
    });
    return row as Map<String, dynamic>;
  }

  /// Calls the void_sale RPC (see supabase/migrations/0026_void_sale.sql),
  /// which atomically transitions a COMPLETED sale to VOIDED, reverses its
  /// inventory and commissions, marks its payment REFUNDED, and writes the
  /// audit record -- all inside the RPC's own transaction. This is the only
  /// sanctioned path to change a sale's status; direct table UPDATEs on
  /// sales/payments are no longer permitted by RLS as of that migration.
  Future<Map<String, dynamic>> voidSale({
    required String businessId,
    required String saleId,
    required String reason,
  }) async {
    final row = await _client.rpc('void_sale', params: {
      'p_business_id': businessId,
      'p_sale_id': saleId,
      'p_reason': reason,
    });
    return row as Map<String, dynamic>;
  }

  /// Calls the record_sale_payment RPC (see
  /// supabase/migrations/0044_record_sale_payment_rpc.sql), which atomically
  /// locks the sale, recomputes the outstanding balance from the payments
  /// table (never from client state), inserts the new payment, and updates
  /// sales.paid_amount/payment_status -- all authoritative server-side.
  /// Returns payment_id/payment_amount/total_amount/paid_amount/
  /// outstanding_balance/payment_status, so the caller never has to
  /// recompute the balance itself; it should re-fetch the sale/payment
  /// history from the server afterward rather than assume local state.
  Future<Map<String, dynamic>> recordSalePayment({
    required String businessId,
    required String saleId,
    required String paymentMethod,
    required String amount,
    String? reference,
  }) async {
    final row = await _client.rpc('record_sale_payment', params: {
      'p_business_id': businessId,
      'p_sale_id': saleId,
      'p_payment_method': paymentMethod,
      'p_amount': amount,
      'p_reference': reference,
    });
    return row as Map<String, dynamic>;
  }
}
