/// A single Consultation record (Phase 5). Read-only from the client's
/// perspective for its identity/snapshot fields -- rows are only ever
/// produced by create_consultation_record (a SECURITY DEFINER RPC that
/// resolves staff/recommended-service snapshots server-side). Narrative
/// fields (consultationNotes/customerConcerns/observations/considerations/
/// assessment/recommendationNotes) may be updated directly (see
/// supabase/migrations/0048_consultations.sql --
/// protect_consultation_identity_columns blocks everything else).
class ConsultationRecord {
  final String id;
  final String businessId;
  final String customerId;
  final String? appointmentId;
  final String staffId;
  final String staffNameSnapshot;
  final String? recommendedServiceId;
  final String? recommendedServiceNameSnapshot;
  final DateTime consultationDate;
  final String? consultationNotes;
  final String? customerConcerns;
  final String? observations;
  final String? considerations;
  final String? assessment;
  final String? recommendationNotes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConsultationRecord({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.appointmentId,
    required this.staffId,
    required this.staffNameSnapshot,
    this.recommendedServiceId,
    this.recommendedServiceNameSnapshot,
    required this.consultationDate,
    this.consultationNotes,
    this.customerConcerns,
    this.observations,
    this.considerations,
    this.assessment,
    this.recommendationNotes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConsultationRecord.fromJson(Map<String, dynamic> json) {
    return ConsultationRecord(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      customerId: json['customer_id'] as String,
      appointmentId: json['appointment_id'] as String?,
      staffId: json['staff_id'] as String,
      staffNameSnapshot: json['staff_name_snapshot'] as String,
      recommendedServiceId: json['recommended_service_id'] as String?,
      recommendedServiceNameSnapshot: json['recommended_service_name_snapshot'] as String?,
      consultationDate: DateTime.parse(json['consultation_date'] as String),
      consultationNotes: json['consultation_notes'] as String?,
      customerConcerns: json['customer_concerns'] as String?,
      observations: json['observations'] as String?,
      considerations: json['considerations'] as String?,
      assessment: json['assessment'] as String?,
      recommendationNotes: json['recommendation_notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
