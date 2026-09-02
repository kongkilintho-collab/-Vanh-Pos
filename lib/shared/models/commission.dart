import 'package:decimal/decimal.dart';

import 'commission_kind.dart';
import 'commission_status.dart';

/// Mirrors the `commissions` table in supabase/migrations/0010_commissions.sql
/// and its Phase 2 extension (0036_commissions_redemption_source.sql) --
/// every field here is a real column on that table, plus two optional
/// display-only fields (staffName, saleReceiptNumber) populated from the
/// profiles/sales joins in CommissionRepository's select. saleId/saleItemId
/// are nullable: a redemption-driven commission (customerPackageRedemptionId
/// set instead) has neither -- see 0036's header for the exactly-one-source
/// invariant enforced server-side.
class Commission {
  final String id;
  final String businessId;
  final String? saleId;
  final String? saleItemId;
  final String? customerPackageRedemptionId;
  final String staffId;
  final String? staffName;
  final String? saleReceiptNumber;
  final CommissionKind commissionType;
  final Decimal commissionRate;
  final Decimal commissionAmount;
  final CommissionStatus status;
  final DateTime createdAt;

  const Commission({
    required this.id,
    required this.businessId,
    this.saleId,
    this.saleItemId,
    this.customerPackageRedemptionId,
    required this.staffId,
    this.staffName,
    this.saleReceiptNumber,
    required this.commissionType,
    required this.commissionRate,
    required this.commissionAmount,
    required this.status,
    required this.createdAt,
  });

  factory Commission.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final sale = json['sales'] as Map<String, dynamic>?;
    return Commission(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      saleId: json['sale_id'] as String?,
      saleItemId: json['sale_item_id'] as String?,
      customerPackageRedemptionId: json['customer_package_redemption_id'] as String?,
      staffId: json['staff_id'] as String,
      staffName: profile?['full_name'] as String?,
      saleReceiptNumber: sale?['receipt_number'] as String?,
      commissionType: CommissionKind.fromDb(json['commission_type'] as String),
      commissionRate: Decimal.parse((json['commission_rate'] ?? 0).toString()),
      commissionAmount: Decimal.parse(json['commission_amount'].toString()),
      status: CommissionStatus.fromDb(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
