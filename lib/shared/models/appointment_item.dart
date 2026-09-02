import 'package:decimal/decimal.dart';

class AppointmentItem {
  final String id;
  final String appointmentId;
  final String serviceId;
  final String? staffId;
  final String nameSnapshot;
  final int durationMinutes;
  final Decimal priceSnapshot;

  const AppointmentItem({
    required this.id,
    required this.appointmentId,
    required this.serviceId,
    this.staffId,
    required this.nameSnapshot,
    required this.durationMinutes,
    required this.priceSnapshot,
  });

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    return AppointmentItem(
      id: json['id'] as String,
      appointmentId: json['appointment_id'] as String,
      serviceId: json['service_id'] as String,
      staffId: json['staff_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String,
      durationMinutes: json['duration_minutes'] as int,
      priceSnapshot: Decimal.parse((json['price_snapshot'] ?? 0).toString()),
    );
  }

  Map<String, dynamic> toBookingJson() {
    return {
      'service_id': serviceId,
      if (staffId != null) 'staff_id': staffId,
      'name_snapshot': nameSnapshot,
      'duration_minutes': durationMinutes,
      'price_snapshot': priceSnapshot.toString(),
    };
  }
}
