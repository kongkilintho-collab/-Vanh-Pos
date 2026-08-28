import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'customer_form_sheet.dart';
import 'customer_providers.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: customerAsync.valueOrNull != null ? Text(customerAsync.valueOrNull!.name) : const Text('Customer'),
        actions: [
          if (customerAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showCustomerFormSheet(context, existing: customerAsync.valueOrNull),
            ),
        ],
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: ErrorBanner(message: friendlyError(err))),
        ),
        data: (customer) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.phone != null) Text(customer.phone!, style: AppTextStyles.body.copyWith(color: AppColors.muted)),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(label: 'Total spent', value: formatMoney(customer.totalSpent)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(label: 'Visits', value: '${customer.visitCount}'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(
                        label: 'Last visit',
                        value: customer.lastVisitAt == null
                            ? '—'
                            : DateFormat('MMM d, y').format(customer.lastVisitAt!.toLocal()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text('Purchase history', style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.md),
                _SalesHistory(customerId: customerId),
                const SizedBox(height: AppSpacing.xxl),
                Text('Notes', style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.md),
                _NotesSection(customerId: customerId, businessId: customer.businessId),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SalesHistory extends ConsumerWidget {
  final String customerId;

  const _SalesHistory({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(customerSalesProvider(customerId));

    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorBanner(message: friendlyError(err)),
      data: (sales) {
        if (sales.isEmpty) {
          return Text('No sales yet.', style: AppTextStyles.body.copyWith(color: AppColors.muted));
        }
        return Column(
          children: [
            for (final sale in sales)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  dense: true,
                  title: Text(sale['receipt_number'] as String, style: AppTextStyles.bodyStrong),
                  subtitle: Text(
                    DateFormat('MMM d, y · h:mm a').format(DateTime.parse(sale['created_at'] as String).toLocal()),
                    style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                  ),
                  trailing: Text(
                    formatMoney(Decimal.parse(sale['total_amount'].toString())),
                    style: AppTextStyles.bodyStrong,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotesSection extends ConsumerStatefulWidget {
  final String customerId;
  final String businessId;

  const _NotesSection({required this.customerId, required this.businessId});

  @override
  ConsumerState<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends ConsumerState<_NotesSection> {
  final _noteController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(customerRepositoryProvider).addNote(
            businessId: widget.businessId,
            customerId: widget.customerId,
            note: text,
          );
      _noteController.clear();
      ref.invalidate(customerNotesProvider(widget.customerId));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(customerNotesProvider(widget.customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: AppSpacing.md)],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _noteController,
                decoration: const InputDecoration(hintText: 'Add a note...'),
                minLines: 1,
                maxLines: 3,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PrimaryButton(label: 'Add', onPressed: _addNote, loading: _submitting, expand: false),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ErrorBanner(message: friendlyError(err)),
          data: (notes) {
            if (notes.isEmpty) {
              return Text('No notes yet.', style: AppTextStyles.body.copyWith(color: AppColors.muted));
            }
            return Column(
              children: [
                for (final note in notes)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(note['note'] as String, style: AppTextStyles.body),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            DateFormat('MMM d, y · h:mm a')
                                .format(DateTime.parse(note['created_at'] as String).toLocal()),
                            style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
