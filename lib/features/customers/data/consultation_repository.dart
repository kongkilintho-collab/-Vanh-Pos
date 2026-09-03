import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/consultation_record.dart';

/// Phase 5 (Consultation / Customer Consultation Records). Reads go
/// straight to consultations (SELECT-only RLS, tenant-scoped by
/// is_member). Creation always goes through create_consultation_record
/// (see supabase/migrations/0048_consultations.sql) -- there is no direct
/// INSERT policy. Narrative-field updates use a direct table UPDATE: RLS
/// (CASHIER+) plus a BEFORE UPDATE trigger restrict it to
/// consultation_notes/customer_concerns/observations/considerations/
/// assessment/recommendation_notes -- identity/snapshot fields are
/// rejected server-side regardless of what this method sends.
class ConsultationRepository {
  final SupabaseClient _client;

  ConsultationRepository(this._client);

  Future<List<ConsultationRecord>> listForCustomer(String businessId, String customerId) async {
    final rows = await _client
        .from('consultations')
        .select()
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('consultation_date', ascending: false);
    return (rows as List).map((r) => ConsultationRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<ConsultationRecord> create({
    required String businessId,
    required String customerId,
    required String staffId,
    required DateTime consultationDate,
    String? appointmentId,
    String? recommendedServiceId,
    String? consultationNotes,
    String? customerConcerns,
    String? observations,
    String? considerations,
    String? assessment,
    String? recommendationNotes,
  }) async {
    final row = await _client.rpc('create_consultation_record', params: {
      'p_business_id': businessId,
      'p_customer_id': customerId,
      'p_staff_id': staffId,
      'p_consultation_date': consultationDate.toUtc().toIso8601String(),
      'p_appointment_id': appointmentId,
      'p_recommended_service_id': recommendedServiceId,
      'p_consultation_notes': consultationNotes,
      'p_customer_concerns': customerConcerns,
      'p_observations': observations,
      'p_considerations': considerations,
      'p_assessment': assessment,
      'p_recommendation_notes': recommendationNotes,
    });
    return ConsultationRecord.fromJson(row as Map<String, dynamic>);
  }

  Future<void> updateNarrative({
    required String id,
    String? consultationNotes,
    String? customerConcerns,
    String? observations,
    String? considerations,
    String? assessment,
    String? recommendationNotes,
  }) async {
    await _client.from('consultations').update({
      'consultation_notes': consultationNotes,
      'customer_concerns': customerConcerns,
      'observations': observations,
      'considerations': considerations,
      'assessment': assessment,
      'recommendation_notes': recommendationNotes,
    }).eq('id', id);
  }
}
