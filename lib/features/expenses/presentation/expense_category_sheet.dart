import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'expense_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showExpenseCategorySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ExpenseCategorySheet(),
  );
}

class _ExpenseCategorySheet extends ConsumerStatefulWidget {
  const _ExpenseCategorySheet();

  @override
  ConsumerState<_ExpenseCategorySheet> createState() =>
      _ExpenseCategorySheetState();
}

class _ExpenseCategorySheetState extends ConsumerState<_ExpenseCategorySheet> {
  final _nameController = TextEditingController();
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;

    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseRepositoryProvider)
          .createCategory(businessId, name);
      _nameController.clear();
      ref.invalidate(expenseCategoriesProvider);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggleActive(String id, bool active) async {
    try {
      await ref.read(expenseRepositoryProvider).setCategoryActive(id, active);
      ref.invalidate(expenseCategoriesProvider);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.expenseCategoriesTitle,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.expenseNewCategoryNameLabel,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PrimaryButton(
                    label: context.l10n.commonAdd,
                    onPressed: _add,
                    loading: _adding,
                    expand: false,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              categoriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) =>
                    ErrorBanner(message: friendlyError(err, context.l10n)),
                data: (categories) {
                  if (categories.isEmpty) {
                    return Text(
                      context.l10n.expenseNoCategoriesYet,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.muted,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final category in categories)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(category.name),
                          trailing: Switch(
                            value: category.active,
                            onChanged: (v) => _toggleActive(category.id, v),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
