import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../shared/models/audit_log.dart';
import '../../../shared/widgets/date_range_filter.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'audit_log_providers.dart';
import '../../../l10n/l10n_extensions.dart';

const _actions = [
  'CREATE',
  'UPDATE',
  'DELETE',
  'VOID',
  'REFUND',
  'PAYMENT',
  'STOCK_ADJUSTMENT',
  'PERMISSION_CHANGE',
  'SETTINGS_CHANGE',
];

const _entityTypes = ['business', 'business_member', 'sale', 'product'];

/// Read-only audit log viewer (F9-3), ADMIN+/OWNER only. Relies entirely on
/// audit_logs_select RLS for its security boundary -- this screen offers no
/// mutation of any kind. Nav visibility in dashboard_shell.dart is a UX
/// convenience only; a lower-ranked caller reaching this screen by other
/// means would simply see an empty/denied result from the same RLS policy.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogListProvider);
    final filter = ref.watch(auditLogFilterProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateRangeFilterBar(
                  selection: filter.range,
                  onChanged: (r) =>
                      ref.read(auditLogFilterProvider.notifier).state = filter
                          .copyWith(range: r),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: filter.action,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.auditActionLabel,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(context.l10n.auditAllActions),
                          ),
                          for (final a in _actions)
                            DropdownMenuItem(value: a, child: Text(a)),
                        ],
                        onChanged: (v) =>
                            ref
                                .read(auditLogFilterProvider.notifier)
                                .state = filter.copyWith(
                              action: v,
                              clearAction: v == null,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: filter.entityType,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.auditEntityLabel,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(context.l10n.auditAllEntities),
                          ),
                          for (final e in _entityTypes)
                            DropdownMenuItem(value: e, child: Text(e)),
                        ],
                        onChanged: (v) =>
                            ref
                                .read(auditLogFilterProvider.notifier)
                                .state = filter.copyWith(
                              entityType: v,
                              clearEntityType: v == null,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ErrorBanner(message: friendlyError(err, context.l10n)),
                ),
              ),
              data: (logs) {
                if (logs.isEmpty) {
                  return Center(
                    child: Text(
                      context.l10n.auditEmptyState,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) =>
                      _AuditLogTile(log: logs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final AuditLog log;

  const _AuditLogTile({required this.log});

  Color _actionColor() => switch (log.action) {
    'DELETE' || 'VOID' => AppColors.danger,
    'REFUND' || 'SETTINGS_CHANGE' => AppColors.warning,
    'PERMISSION_CHANGE' => AppColors.info,
    _ => AppColors.success,
  };

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  Widget build(BuildContext context) {
    final hasDetail =
        log.oldData != null || log.newData != null || log.metadata != null;
    return Card(
      child: ExpansionTile(
        enabled: hasDetail,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 0,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: _actionColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                log.action,
                style: AppTextStyles.caption.copyWith(color: _actionColor()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${log.entityType}${log.entityId != null ? ' · ${log.entityId!.substring(0, 8)}' : ''}',
                style: AppTextStyles.bodyStrong,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${log.actorName ?? context.l10n.auditSystemActor} · ${DateFormat('MMM d, y · h:mm a').format(log.createdAt.toLocal())}',
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
        children: [
          if (hasDetail)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (log.oldData != null)
                    _JsonBlock(
                      label: context.l10n.auditBefore,
                      data: log.oldData!,
                      encoder: _encoder,
                    ),
                  if (log.newData != null)
                    _JsonBlock(
                      label: context.l10n.auditAfter,
                      data: log.newData!,
                      encoder: _encoder,
                    ),
                  if (log.metadata != null)
                    _JsonBlock(
                      label: context.l10n.auditDetails,
                      data: log.metadata!,
                      encoder: _encoder,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final String label;
  final Map<String, dynamic> data;
  final JsonEncoder encoder;

  const _JsonBlock({
    required this.label,
    required this.data,
    required this.encoder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.captionStrong.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(encoder.convert(data), style: AppTextStyles.caption),
          ),
        ],
      ),
    );
  }
}
