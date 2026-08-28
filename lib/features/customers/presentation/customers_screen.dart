import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/customer.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'customer_detail_screen.dart';
import 'customer_form_sheet.dart';
import 'customer_providers.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCustomerFormSheet(context),
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Add customer'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search by name or phone',
              ),
              onChanged: (v) => ref.read(customerSearchQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: customersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ErrorBanner(message: friendlyError(err)),
                ),
              ),
              data: (customers) {
                if (customers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups_outlined, size: 40, color: AppColors.muted),
                          const SizedBox(height: AppSpacing.md),
                          Text('No customers yet', style: AppTextStyles.title),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Add your first customer, or they\'ll be created automatically at checkout.',
                            style: AppTextStyles.body.copyWith(color: AppColors.muted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 88),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _CustomerTile(customer: customers[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(customer.name, style: AppTextStyles.bodyStrong),
        subtitle: Text(
          customer.phone ?? 'No phone on file',
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(customer.totalSpent), style: AppTextStyles.bodyStrong),
            Text('${customer.visitCount} visits', style: AppTextStyles.caption.copyWith(color: AppColors.muted)),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: customer.id)),
        ),
      ),
    );
  }
}
