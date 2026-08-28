import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/expense.dart';
import '../../../shared/models/expense_category.dart';

/// Expense tracking (Day 4). Every write here is a direct table insert/
/// update against `expenses`/`expense_categories`, both already
/// RLS-protected to ADMIN+ (see expenses_insert/expense_categories_insert
/// in 0015_rls_policies.sql) -- no SECURITY DEFINER write path needed,
/// since neither table has a cross-table atomicity requirement the way
/// stock adjustments do.
class ExpenseRepository {
  final SupabaseClient _client;

  ExpenseRepository(this._client);

  Future<List<ExpenseCategory>> listCategories(String businessId, {bool activeOnly = false}) async {
    var builder = _client.from('expense_categories').select().eq('business_id', businessId);
    if (activeOnly) builder = builder.eq('active', true);
    final rows = await builder.order('name');
    return (rows as List).map((r) => ExpenseCategory.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<ExpenseCategory> createCategory(String businessId, String name) async {
    final row = await _client
        .from('expense_categories')
        .insert({'business_id': businessId, 'name': name})
        .select()
        .single();
    return ExpenseCategory.fromJson(row);
  }

  Future<void> setCategoryActive(String id, bool active) async {
    await _client.from('expense_categories').update({'active': active}).eq('id', id);
  }

  Future<List<Expense>> listForBusiness(
    String businessId, {
    String? categoryId,
    DateTime? from,
    DateTime? to,
  }) async {
    var builder = _client
        .from('expenses')
        .select('*, expense_categories(name)')
        .eq('business_id', businessId);

    if (categoryId != null) builder = builder.eq('category_id', categoryId);
    if (from != null) builder = builder.gte('expense_date', from.toIso8601String().split('T').first);
    if (to != null) builder = builder.lte('expense_date', to.toIso8601String().split('T').first);

    final rows = await builder.order('expense_date', ascending: false).limit(200);
    return (rows as List).map((r) => Expense.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Expense> create(Expense expense, {required String createdBy}) async {
    final row = await _client
        .from('expenses')
        .insert({...expense.toInsertJson(businessId: expense.businessId), 'created_by': createdBy})
        .select('*, expense_categories(name)')
        .single();
    return Expense.fromJson(row);
  }

  Future<Expense> update(Expense expense) async {
    final row = await _client
        .from('expenses')
        .update(expense.toInsertJson(businessId: expense.businessId))
        .eq('id', expense.id)
        .select('*, expense_categories(name)')
        .single();
    return Expense.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }
}
