class PackageItem {
  final String id;
  final String packageId;
  final String serviceId;
  final String? serviceName;
  final int sessionCount;

  const PackageItem({
    required this.id,
    required this.packageId,
    required this.serviceId,
    this.serviceName,
    required this.sessionCount,
  });

  factory PackageItem.fromJson(Map<String, dynamic> json) {
    final service = json['services'] as Map<String, dynamic>?;
    return PackageItem(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      serviceId: json['service_id'] as String,
      serviceName: service?['name'] as String?,
      sessionCount: json['session_count'] as int,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId, required String packageId}) {
    return {
      'business_id': businessId,
      'package_id': packageId,
      'service_id': serviceId,
      'session_count': sessionCount,
    };
  }
}
