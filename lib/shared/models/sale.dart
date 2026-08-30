import 'package:decimal/decimal.dart';

class Sale {
  final String id;
  final String receiptNumber;
  final Decimal subtotal;
  final Decimal discountAmount;
  final Decimal taxAmount;
  final Decimal totalAmount;
  final Decimal paidAmount;
  final Decimal changeAmount;
  final String status;
  final String paymentStatus;
  final DateTime createdAt;
  final String? voidReason;
  final String? voidedBy;
  final DateTime? voidedAt;

  const Sale({
    required this.id,
    required this.receiptNumber,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.changeAmount,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    this.voidReason,
    this.voidedBy,
    this.voidedAt,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String,
      receiptNumber: json['receipt_number'] as String,
      subtotal: Decimal.parse(json['subtotal'].toString()),
      discountAmount: Decimal.parse((json['discount_amount'] ?? 0).toString()),
      taxAmount: Decimal.parse((json['tax_amount'] ?? 0).toString()),
      totalAmount: Decimal.parse(json['total_amount'].toString()),
      paidAmount: Decimal.parse((json['paid_amount'] ?? 0).toString()),
      changeAmount: Decimal.parse((json['change_amount'] ?? 0).toString()),
      status: json['status'] as String,
      paymentStatus: json['payment_status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      voidReason: json['void_reason'] as String?,
      voidedBy: json['voided_by'] as String?,
      voidedAt: json['voided_at'] == null ? null : DateTime.parse(json['voided_at'] as String),
    );
  }
}
