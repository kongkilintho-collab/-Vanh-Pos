import 'follow_up_status.dart';

DateTime _startOfLocalDay(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// A single staff-managed customer Follow-up (Phase 6). Read-only from the
/// client's perspective for its lifecycle fields (assignedStaffId/
/// assignedStaffNameSnapshot/dueDate/status/completedAt/completedBy) --
/// rows are only ever produced/mutated by create_follow_up/
/// reschedule_follow_up/set_follow_up_status (see
/// supabase/migrations/0049_follow_ups_and_line_oa.sql --
/// protect_follow_up_identity_columns blocks everything else). Only
/// followUpNotes may be updated directly.
///
/// DUE/OVERDUE/UPCOMING are deliberately NOT stored anywhere -- the three
/// getters below are pure, read-time derivations from (status, dueDate)
/// compared against calendar days (never a naive string/date compare),
/// mirroring the same derivation rule the server-side query filters use
/// in FollowUpRepository.listForBusiness.
class FollowUp {
  final String id;
  final String businessId;
  final String customerId;
  final String assignedStaffId;
  final String assignedStaffNameSnapshot;
  final String? consultationId;
  final String? treatmentHistoryId;
  final String? appointmentId;
  final DateTime dueDate;
  final FollowUpStatus status;
  final String? followUpNotes;
  final DateTime? completedAt;
  final String? completedBy;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName;

  const FollowUp({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.assignedStaffId,
    required this.assignedStaffNameSnapshot,
    this.consultationId,
    this.treatmentHistoryId,
    this.appointmentId,
    required this.dueDate,
    required this.status,
    this.followUpNotes,
    this.completedAt,
    this.completedBy,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
  });

  bool get isOverdue {
    if (status != FollowUpStatus.pending) return false;
    return _startOfLocalDay(dueDate).isBefore(_startOfLocalDay(DateTime.now()));
  }

  bool get isDueToday {
    if (status != FollowUpStatus.pending) return false;
    return _startOfLocalDay(dueDate).isAtSameMomentAs(_startOfLocalDay(DateTime.now()));
  }

  bool get isUpcoming {
    if (status != FollowUpStatus.pending) return false;
    return _startOfLocalDay(dueDate).isAfter(_startOfLocalDay(DateTime.now()));
  }

  factory FollowUp.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'] as Map<String, dynamic>?;
    return FollowUp(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      customerId: json['customer_id'] as String,
      assignedStaffId: json['assigned_staff_id'] as String,
      assignedStaffNameSnapshot: json['assigned_staff_name_snapshot'] as String,
      consultationId: json['consultation_id'] as String?,
      treatmentHistoryId: json['treatment_history_id'] as String?,
      appointmentId: json['appointment_id'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String),
      status: FollowUpStatus.fromDb(json['status'] as String),
      followUpNotes: json['follow_up_notes'] as String?,
      completedAt: json['completed_at'] == null ? null : DateTime.parse(json['completed_at'] as String),
      completedBy: json['completed_by'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      customerName: customer?['name'] as String?,
    );
  }
}
