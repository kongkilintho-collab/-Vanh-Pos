import 'package:decimal/decimal.dart';

class AppointmentItem {
  final String id;
  final String appointmentId;
  final String serviceId;
  final String? staffId;
  final String nameSnapshot;
  final int durationMinutes;
  final Decimal priceSnapshot;
  final String? customerPackageItemId;
  final String? packageNameSnapshot;
  final int? packageTotalSessions;
  final int? packageUsedSessions;

  const AppointmentItem({
    required this.id,
    required this.appointmentId,
    required this.serviceId,
    this.staffId,
    required this.nameSnapshot,
    required this.durationMinutes,
    required this.priceSnapshot,
    this.customerPackageItemId,
    this.packageNameSnapshot,
    this.packageTotalSessions,
    this.packageUsedSessions,
  });

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    final packageItem = json['customer_package_items'] as Map<String, dynamic>?;
    return AppointmentItem(
      id: json['id'] as String,
      appointmentId: json['appointment_id'] as String,
      serviceId: json['service_id'] as String,
      staffId: json['staff_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String,
      durationMinutes: json['duration_minutes'] as int,
      priceSnapshot: Decimal.parse((json['price_snapshot'] ?? 0).toString()),
      customerPackageItemId: json['customer_package_item_id'] as String?,
      packageNameSnapshot: packageItem?['name_snapshot'] as String?,
      packageTotalSessions: packageItem?['total_sessions'] as int?,
      packageUsedSessions: packageItem?['used_sessions'] as int?,
    );
  }

  Map<String, dynamic> toBookingJson() {
    return {
      'service_id': serviceId,
      if (staffId != null) 'staff_id': staffId,
      'name_snapshot': nameSnapshot,
      'duration_minutes': durationMinutes,
      'price_snapshot': priceSnapshot.toString(),
      if (customerPackageItemId != null) 'customer_package_item_id': customerPackageItemId,
    };
  }
}
