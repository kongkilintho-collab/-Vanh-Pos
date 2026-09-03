/// A single Customer Treatment History entry (Phase 4). Read-only from the
/// client's perspective for its identity/snapshot fields -- rows are only
/// ever produced by set_appointment_status (on appointment completion) or
/// create_treatment_record (manual/walk-in entry), both SECURITY DEFINER
/// RPCs that resolve service/staff snapshots server-side. Narrative fields
/// (notes/result/customerFeedback/beforeAfterReference/followUpDate) may
/// be updated directly (see supabase/migrations/0047_treatment_history.sql
/// -- protect_treatment_history_identity_columns blocks everything else).
class TreatmentRecord {
  final String id;
  final String businessId;
  final String customerId;
  final String? appointmentId;
  final String? appointmentItemId;
  final String? saleId;
  final String serviceId;
  final String staffId;
  final String serviceNameSnapshot;
  final String staffNameSnapshot;
  final DateTime treatmentDate;
  final String? notes;
  final String? result;
  final String? customerFeedback;
  final String? beforeAfterReference;
  final DateTime? followUpDate;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TreatmentRecord({
    required this.id,
    required this.businessId,
    required this.customerId,
    this.appointmentId,
    this.appointmentItemId,
    this.saleId,
    required this.serviceId,
    required this.staffId,
    required this.serviceNameSnapshot,
    required this.staffNameSnapshot,
    required this.treatmentDate,
    this.notes,
    this.result,
    this.customerFeedback,
    this.beforeAfterReference,
    this.followUpDate,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TreatmentRecord.fromJson(Map<String, dynamic> json) {
    return TreatmentRecord(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      customerId: json['customer_id'] as String,
      appointmentId: json['appointment_id'] as String?,
      appointmentItemId: json['appointment_item_id'] as String?,
      saleId: json['sale_id'] as String?,
      serviceId: json['service_id'] as String,
      staffId: json['staff_id'] as String,
      serviceNameSnapshot: json['service_name_snapshot'] as String,
      staffNameSnapshot: json['staff_name_snapshot'] as String,
      treatmentDate: DateTime.parse(json['treatment_date'] as String),
      notes: json['notes'] as String?,
      result: json['result'] as String?,
      customerFeedback: json['customer_feedback'] as String?,
      beforeAfterReference: json['before_after_reference'] as String?,
      followUpDate: json['follow_up_date'] == null
          ? null
          : DateTime.parse(json['follow_up_date'] as String),
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
