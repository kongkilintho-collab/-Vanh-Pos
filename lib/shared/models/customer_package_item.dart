class CustomerPackageItem {
  final String id;
  final String customerPackageId;
  final String? serviceId;
  final String nameSnapshot;
  final int totalSessions;
  final int usedSessions;

  const CustomerPackageItem({
    required this.id,
    required this.customerPackageId,
    this.serviceId,
    required this.nameSnapshot,
    required this.totalSessions,
    required this.usedSessions,
  });

  int get remainingSessions => totalSessions - usedSessions;

  factory CustomerPackageItem.fromJson(Map<String, dynamic> json) {
    return CustomerPackageItem(
      id: json['id'] as String,
      customerPackageId: json['customer_package_id'] as String,
      serviceId: json['service_id'] as String?,
      nameSnapshot: json['name_snapshot'] as String,
      totalSessions: json['total_sessions'] as int,
      usedSessions: json['used_sessions'] as int? ?? 0,
    );
  }
}
