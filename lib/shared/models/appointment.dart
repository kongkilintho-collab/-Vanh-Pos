import 'appointment_item.dart';
import 'appointment_status.dart';

class Appointment {
  final String id;
  final String businessId;
  final String? branchId;
  final String? customerId;
  final String? customerName;
  final String staffId;
  final String staffName;
  final DateTime startAt;
  final DateTime endAt;
  final AppointmentStatus status;
  final String? notes;
  final String? cancelReason;
  final String? saleId;
  final List<AppointmentItem> items;

  const Appointment({
    required this.id,
    required this.businessId,
    this.branchId,
    this.customerId,
    this.customerName,
    required this.staffId,
    required this.staffName,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.notes,
    this.cancelReason,
    this.saleId,
    this.items = const [],
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'] as Map<String, dynamic>?;
    final staff = json['profiles'] as Map<String, dynamic>?;
    final rawItems = json['appointment_items'] as List<dynamic>?;
    return Appointment(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      customerId: json['customer_id'] as String?,
      customerName: customer?['name'] as String?,
      staffId: json['staff_id'] as String,
      staffName: staff?['full_name'] as String? ?? 'Unknown',
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      status: AppointmentStatus.fromDb(json['status'] as String),
      notes: json['notes'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      saleId: json['sale_id'] as String?,
      items: rawItems == null
          ? const []
          : rawItems
              .map((r) => AppointmentItem.fromJson(r as Map<String, dynamic>))
              .toList(),
    );
  }
}
