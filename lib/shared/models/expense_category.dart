/// Mirrors the `expense_categories` table in
/// supabase/migrations/0011_expenses.sql.
class ExpenseCategory {
  final String id;
  final String businessId;
  final String name;
  final bool active;

  const ExpenseCategory({
    required this.id,
    required this.businessId,
    required this.name,
    required this.active,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson({required String businessId}) {
    return {
      'business_id': businessId,
      'name': name,
      'active': active,
    };
  }
}
