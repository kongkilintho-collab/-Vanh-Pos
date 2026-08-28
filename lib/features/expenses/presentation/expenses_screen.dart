import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/expense.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'expense_category_sheet.dart';
import 'expense_form_sheet.dart';
import 'expense_providers.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesListProvider);
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final filter = ref.watch(expenseCategoryFilterProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseFormSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: categoriesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (categories) => DropdownButtonFormField<String?>(
                      initialValue: filter,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All categories')),
                        for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => ref.read(expenseCategoryFilterProvider.notifier).state = v,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Manage categories',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: () => showExpenseCategorySheet(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
              ),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.muted),
                          const SizedBox(height: AppSpacing.md),
                          Text('No expenses recorded', style: AppTextStyles.title),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Track rent, utilities, and other business costs here.',
                            style: AppTextStyles.body.copyWith(color: AppColors.muted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final total = expenses.fold<Decimal>(Decimal.zero, (sum, e) => sum + e.amount);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Row(
                        children: [
                          Text('Total: ', style: AppTextStyles.body.copyWith(color: AppColors.muted)),
                          Text(formatMoney(total), style: AppTextStyles.bodyStrong),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 88),
                        itemCount: expenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _ExpenseTile(expense: expenses[index]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  final Expense expense;

  const _ExpenseTile({required this.expense});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(expenseRepositoryProvider).delete(expense.id);
      ref.invalidate(expensesListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        title: Text(expense.categoryName ?? 'Uncategorized', style: AppTextStyles.bodyStrong),
        subtitle: Text(
          [
            DateFormat('MMM d, y').format(expense.expenseDate),
            expense.paymentMethod.label,
            if (expense.description != null && expense.description!.isNotEmpty) expense.description!,
          ].join(' · '),
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatMoney(expense.amount), style: AppTextStyles.bodyStrong),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) {
                if (value == 'edit') showExpenseFormSheet(context, existing: expense);
                if (value == 'delete') _delete(context, ref);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
