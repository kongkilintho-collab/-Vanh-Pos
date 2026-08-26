class Business {
  final String id;
  final String name;
  final String? logoUrl;
  final String? phone;
  final String? email;
  final String? address;
  final String currency;
  final String timezone;
  final bool taxEnabled;
  final double taxRate;

  const Business({
    required this.id,
    required this.name,
    this.logoUrl,
    this.phone,
    this.email,
    this.address,
    required this.currency,
    required this.timezone,
    required this.taxEnabled,
    required this.taxRate,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      currency: json['currency'] as String? ?? 'LAK',
      timezone: json['timezone'] as String? ?? 'Asia/Vientiane',
      taxEnabled: json['tax_enabled'] as bool? ?? false,
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0,
    );
  }
}
