import 'package:decimal/decimal.dart';

import 'payment_method.dart';

/// Mirrors the `expenses` table in supabase/migrations/0011_expenses.sql,
/// plus one optional display-only field (categoryName) populated from the
/// expense_categories join in ExpenseRepository's select.
class Expense {
  final String id;
  final String businessId;
  final String? branchId;
  final String? categoryId;
  final String? categoryName;
  final Decimal amount;
  final PaymentMethod paymentMethod;
  final String? description;
  final DateTime expenseDate;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.businessId,
    this.branchId,
    this.categoryId,
    this.categoryName,
    required this.amount,
    required this.paymentMethod,
    this.description,
    required this.expenseDate,
    required this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final category = json['expense_categories'] as Map<String, dynamic>?;
    return Expense(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName: category?['name'] as String?,
      amount: Decimal.parse(json['amount'].toString()),
      paymentMethod: PaymentMethod.fromDb(json['payment_method'] as String),
      description: json['description'] as String?,
      expenseDate: DateTime.parse(json['expense_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      if (categoryId != null) 'category_id': categoryId,
      'amount': amount.toString(),
      'payment_method': paymentMethod.dbValue,
      if (description != null && description!.isNotEmpty) 'description': description,
      'expense_date': expenseDate.toIso8601String().split('T').first,
    };
  }
}
