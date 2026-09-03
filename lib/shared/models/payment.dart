import 'package:decimal/decimal.dart';

/// A single payment transaction against a sale. Read-only from the client's
/// perspective -- rows are only ever produced by complete_sale or
/// record_sale_payment (both SECURITY DEFINER RPCs); the client cannot
/// INSERT, UPDATE, or DELETE a payment directly (see
/// supabase/migrations/0025_revoke_direct_financial_insert_paths.sql and
/// 0026_void_sale.sql).
class Payment {
  final String id;
  final String saleId;
  final String paymentMethod;
  final Decimal amount;
  final String? reference;
  final String status;
  final DateTime createdAt;

  const Payment({
    required this.id,
    required this.saleId,
    required this.paymentMethod,
    required this.amount,
    this.reference,
    required this.status,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      paymentMethod: json['payment_method'] as String,
      amount: Decimal.parse(json['amount'].toString()),
      reference: json['reference'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
