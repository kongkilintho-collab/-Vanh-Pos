import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/expense.dart';
import '../../../shared/models/payment_method.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'expense_providers.dart';

Future<void> showExpenseFormSheet(BuildContext context, {Expense? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExpenseFormSheet(existing: existing),
  );
}

class _ExpenseFormSheet extends ConsumerStatefulWidget {
  final Expense? existing;

  const _ExpenseFormSheet({this.existing});

  @override
  ConsumerState<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<_ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(text: widget.existing?.amount.toString() ?? '');
  late final _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
  String? _categoryId;
  late PaymentMethod _paymentMethod = widget.existing?.paymentMethod ?? PaymentMethod.cash;
  late DateTime _expenseDate = widget.existing?.expenseDate ?? DateTime.now();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?.categoryId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _expenseDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    final userId = ref.read(currentUserProvider)?.id;
    if (businessId == null || userId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expense = Expense(
        id: widget.existing?.id ?? '',
        businessId: businessId,
        categoryId: _categoryId,
        amount: Decimal.parse(_amountController.text.trim()),
        paymentMethod: _paymentMethod,
        description: _descriptionController.text.trim(),
        expenseDate: _expenseDate,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      final repo = ref.read(expenseRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(expense, createdBy: userId);
      } else {
        await repo.update(expense);
      }

      ref.invalidate(expensesListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final categoriesAsync = ref.watch(expenseCategoriesProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isEditing ? 'Edit expense' : 'Add expense', style: AppTextStyles.headline),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (LAK)'),
                validator: (v) {
                  final parsed = Decimal.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed <= Decimal.zero) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              categoriesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => ErrorBanner(message: friendlyError(err)),
                data: (categories) {
                  final options = categories.where((c) => c.active || c.id == _categoryId).toList();
                  return DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category (optional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('No category')),
                      for (final c in options) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label))).toList(),
                onChanged: (m) => setState(() => _paymentMethod = m ?? _paymentMethod),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text('${_expenseDate.year}-${_expenseDate.month.toString().padLeft(2, '0')}-${_expenseDate.day.toString().padLeft(2, '0')}'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: isEditing ? 'Save changes' : 'Add expense',
                onPressed: _submit,
                loading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
