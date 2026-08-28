import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/expense.dart';
import '../../../shared/models/expense_category.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../data/expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(supabaseClientProvider));
});

final expenseCategoriesProvider = FutureProvider.autoDispose<List<ExpenseCategory>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  return ref.watch(expenseRepositoryProvider).listCategories(membership.business.id);
});

final expenseCategoryFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

final expensesListProvider = FutureProvider.autoDispose<List<Expense>>((ref) async {
  final membership = ref.watch(currentMembershipProvider);
  if (membership == null) return const [];
  final categoryId = ref.watch(expenseCategoryFilterProvider);
  return ref.watch(expenseRepositoryProvider).listForBusiness(membership.business.id, categoryId: categoryId);
});
