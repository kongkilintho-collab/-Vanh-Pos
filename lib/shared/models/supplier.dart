/// Mirrors the `suppliers` table in supabase/migrations/0006_catalog.sql.
class Supplier {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final bool active;

  const Supplier({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    required this.active,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      'name': name,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      if (email != null && email!.isNotEmpty) 'email': email,
      if (address != null && address!.isNotEmpty) 'address': address,
      'active': active,
    };
  }
}
