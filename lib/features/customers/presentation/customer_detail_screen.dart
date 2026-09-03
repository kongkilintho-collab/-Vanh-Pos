import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/customer_package_status.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../packages/presentation/customer_package_providers.dart';
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
        title: customerAsync.valueOrNull != null
            ? Text(customerAsync.valueOrNull!.name)
            : Text(context.l10n.customersFallbackTitle),
        actions: [
          if (customerAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.l10n.customersEditTitle,
              onPressed: () => showCustomerFormSheet(
                context,
                existing: customerAsync.valueOrNull,
              ),
            ),
        ],
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ErrorBanner(message: friendlyError(err, context.l10n)),
          ),
        ),
        data: (customer) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.phone != null)
                  Text(
                    customer.phone!,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        label: context.l10n.customersTotalSpent,
                        value: formatMoney(customer.totalSpent),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(
                        label: context.l10n.customersVisits,
                        value: '${customer.visitCount}',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(
                        label: context.l10n.customersLastVisit,
                        value: customer.lastVisitAt == null
                            ? '—'
                            : DateFormat(
                                'MMM d, y',
                              ).format(customer.lastVisitAt!.toLocal()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  context.l10n.customersPurchaseHistory,
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: AppSpacing.md),
                _SalesHistory(customerId: customerId),
                const SizedBox(height: AppSpacing.xxl),
                Text(context.l10n.pkgMembershipsTitle, style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.md),
                _MembershipsSection(customerId: customerId),
                const SizedBox(height: AppSpacing.xxl),
                Text(context.l10n.customersNotes, style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.md),
                _NotesSection(
                  customerId: customerId,
                  businessId: customer.businessId,
                ),
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
            Text(
              label,
              style: AppTextStyles.caption.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
      error: (err, _) => ErrorBanner(message: friendlyError(err, context.l10n)),
      data: (sales) {
        if (sales.isEmpty) {
          return Text(
            context.l10n.customersNoSalesYet,
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          );
        }
        return Column(
          children: [
            for (final sale in sales)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  dense: true,
                  title: Text(
                    sale['receipt_number'] as String,
                    style: AppTextStyles.bodyStrong,
                  ),
                  subtitle: Text(
                    DateFormat('MMM d, y · h:mm a').format(
                      DateTime.parse(sale['created_at'] as String).toLocal(),
                    ),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.muted,
                    ),
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

class _MembershipsSection extends ConsumerWidget {
  final String customerId;

  const _MembershipsSection({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(customerPackagesForCustomerProvider(customerId));

    return packagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorBanner(message: friendlyError(err, context.l10n)),
      data: (customerPackages) {
        if (customerPackages.isEmpty) {
          return Text(
            context.l10n.pkgNoMembershipsYet,
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          );
        }
        return Column(
          children: [
            for (final cp in customerPackages)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(cp.nameSnapshot, style: AppTextStyles.bodyStrong),
                          ),
                          _MembershipStatusChip(status: cp.status, isExpired: cp.isExpired),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cp.expiresAt == null
                            ? context.l10n.pkgNeverExpires
                            : context.l10n.pkgExpiresOn(
                                DateFormat('MMM d, y').format(cp.expiresAt!.toLocal()),
                              ),
                        style: AppTextStyles.caption.copyWith(color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final item in cp.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            context.l10n.pkgItemRemaining(
                              item.nameSnapshot,
                              item.remainingSessions,
                              item.totalSessions,
                            ),
                            style: AppTextStyles.body,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MembershipStatusChip extends StatelessWidget {
  final CustomerPackageStatus status;
  final bool isExpired;

  const _MembershipStatusChip({required this.status, required this.isExpired});

  @override
  Widget build(BuildContext context) {
    final effective = status == CustomerPackageStatus.active && isExpired
        ? CustomerPackageStatus.expired
        : status;
    final color = switch (effective) {
      CustomerPackageStatus.active => AppColors.success,
      CustomerPackageStatus.expired => AppColors.warning,
      CustomerPackageStatus.cancelled => AppColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        effective.label(context.l10n),
        style: AppTextStyles.caption.copyWith(color: color),
      ),
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
      await ref
          .read(customerRepositoryProvider)
          .addNote(
            businessId: widget.businessId,
            customerId: widget.customerId,
            note: text,
          );
      _noteController.clear();
      ref.invalidate(customerNotesProvider(widget.customerId));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
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
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  hintText: context.l10n.customersAddNoteHint,
                ),
                minLines: 1,
                maxLines: 3,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PrimaryButton(
              label: context.l10n.commonAdd,
              onPressed: _addNote,
              loading: _submitting,
              expand: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) =>
              ErrorBanner(message: friendlyError(err, context.l10n)),
          data: (notes) {
            if (notes.isEmpty) {
              return Text(
                context.l10n.customersNoNotesYet,
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              );
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
                          Text(
                            note['note'] as String,
                            style: AppTextStyles.body,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            DateFormat('MMM d, y · h:mm a').format(
                              DateTime.parse(
                                note['created_at'] as String,
                              ).toLocal(),
                            ),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.muted,
                            ),
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
