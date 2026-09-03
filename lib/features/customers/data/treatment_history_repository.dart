import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/treatment_record.dart';

/// Phase 4 (Customer Treatment History). Reads go straight to
/// treatment_history (SELECT-only RLS, tenant-scoped by is_member).
/// Creation always goes through create_treatment_record (see
/// supabase/migrations/0047_treatment_history.sql) -- there is no direct
/// INSERT policy. Narrative-field updates use a direct table UPDATE: RLS
/// (CASHIER+) plus a BEFORE UPDATE trigger restrict it to
/// notes/result/customer_feedback/before_after_reference/follow_up_date --
/// identity/snapshot fields are rejected server-side regardless of what
/// this method sends.
class TreatmentHistoryRepository {
  final SupabaseClient _client;

  TreatmentHistoryRepository(this._client);

  Future<List<TreatmentRecord>> listForCustomer(String businessId, String customerId) async {
    final rows = await _client
        .from('treatment_history')
        .select()
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('treatment_date', ascending: false);
    return (rows as List).map((r) => TreatmentRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<TreatmentRecord> create({
    required String businessId,
    required String customerId,
    required String serviceId,
    required String staffId,
    required DateTime treatmentDate,
    String? appointmentId,
    String? appointmentItemId,
    String? saleId,
    String? notes,
    String? result,
    String? customerFeedback,
    String? beforeAfterReference,
    DateTime? followUpDate,
  }) async {
    final row = await _client.rpc('create_treatment_record', params: {
      'p_business_id': businessId,
      'p_customer_id': customerId,
      'p_service_id': serviceId,
      'p_staff_id': staffId,
      'p_treatment_date': treatmentDate.toUtc().toIso8601String(),
      'p_appointment_id': appointmentId,
      'p_appointment_item_id': appointmentItemId,
      'p_sale_id': saleId,
      'p_notes': notes,
      'p_result': result,
      'p_customer_feedback': customerFeedback,
      'p_before_after_reference': beforeAfterReference,
      'p_follow_up_date': followUpDate == null
          ? null
          : '${followUpDate.year.toString().padLeft(4, '0')}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}',
    });
    return TreatmentRecord.fromJson(row as Map<String, dynamic>);
  }

  Future<void> updateNarrative({
    required String id,
    String? notes,
    String? result,
    String? customerFeedback,
    String? beforeAfterReference,
    DateTime? followUpDate,
  }) async {
    await _client.from('treatment_history').update({
      'notes': notes,
      'result': result,
      'customer_feedback': customerFeedback,
      'before_after_reference': beforeAfterReference,
      'follow_up_date': followUpDate == null
          ? null
          : '${followUpDate.year.toString().padLeft(4, '0')}-${followUpDate.month.toString().padLeft(2, '0')}-${followUpDate.day.toString().padLeft(2, '0')}',
    }).eq('id', id);
  }
}
