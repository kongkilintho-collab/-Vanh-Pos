import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/appointment_item.dart';
import '../../../shared/models/customer_package.dart';
import '../../../shared/models/customer_package_item.dart';
import '../../../shared/models/customer_package_status.dart';
import '../../../shared/models/service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../packages/presentation/customer_package_providers.dart';
import '../../pos/presentation/customer_picker_sheet.dart';
import '../../pos/presentation/pos_providers.dart';
import '../../services/presentation/service_providers.dart';
import 'appointment_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<void> showAppointmentFormSheet(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AppointmentFormSheet(initialDate: initialDate),
  );
}

class _AppointmentFormSheet extends ConsumerStatefulWidget {
  final DateTime? initialDate;

  const _AppointmentFormSheet({this.initialDate});

  @override
  ConsumerState<_AppointmentFormSheet> createState() =>
      _AppointmentFormSheetState();
}

class _AppointmentFormSheetState extends ConsumerState<_AppointmentFormSheet> {
  late DateTime _date = widget.initialDate ?? DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  String? _staffId;
  String? _customerId;
  String? _customerName;
  final _notesController = TextEditingController();
  final Set<String> _selectedServiceIds = {};
  final Map<String, String> _entitlementByService = {};

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickCustomer() async {
    final customer = await showCustomerPickerSheet(context);
    if (customer != null) {
      setState(() {
        _customerId = customer.id;
        _customerName = customer.name;
        // Entitlement eligibility is customer-specific -- clear any prior
        // selection rather than carry it over to a different customer.
        _entitlementByService.clear();
      });
    }
  }

  /// Client-side filtering only, for UX convenience -- book_appointment and
  /// set_appointment_status both re-validate ownership/service-match/
  /// active/expiry/remaining-sessions server-side regardless of what's
  /// shown here (see 0037/0039's headers).
  List<CustomerPackageItem> _eligibleEntitlements(
    List<CustomerPackage> customerPackages,
    String serviceId,
  ) {
    final result = <CustomerPackageItem>[];
    for (final cp in customerPackages) {
      if (cp.status != CustomerPackageStatus.active || cp.isExpired) continue;
      for (final item in cp.items) {
        if (item.serviceId == serviceId && item.remainingSessions > 0) {
          result.add(item);
        }
      }
    }
    return result;
  }

  Future<void> _submit(List<Service> services) async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null || _staffId == null) return;
    if (_selectedServiceIds.isEmpty) {
      setState(() => _error = context.l10n.apptSelectAtLeastOneService);
      return;
    }

    final startAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final selected = services.where((s) => _selectedServiceIds.contains(s.id));
    final totalMinutes = selected.fold<int>(
      0,
      (sum, s) => sum + s.durationMinutes,
    );
    final endAt = startAt.add(Duration(minutes: totalMinutes));
    final items = selected
        .map(
          (s) => AppointmentItem(
            id: '',
            appointmentId: '',
            serviceId: s.id,
            nameSnapshot: s.name,
            durationMinutes: s.durationMinutes,
            priceSnapshot: s.price,
            customerPackageItemId: _entitlementByService[s.id],
          ),
        )
        .toList();

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(appointmentRepositoryProvider).book(
            businessId: businessId,
            customerId: _customerId,
            staffId: _staffId!,
            startAt: startAt,
            endAt: endAt,
            items: items,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      ref.invalidate(appointmentsForRangeProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final servicesAsync = ref.watch(servicesListProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.apptBookTitle, style: AppTextStyles.headline),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_customerName ?? context.l10n.apptWalkIn),
              subtitle: Text(context.l10n.apptCustomerOptional),
              trailing: TextButton(
                onPressed: _pickCustomer,
                child: Text(context.l10n.commonChoose),
              ),
            ),
            const Divider(),
            staffAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(friendlyError(e, context.l10n)),
              data: (staff) => DropdownButtonFormField<String>(
                initialValue: _staffId,
                decoration: InputDecoration(
                  labelText: context.l10n.apptStaffLabel,
                ),
                items: staff
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.userId,
                        child: Text(s.fullName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _staffId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(_time.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l10n.apptServicesLabel, style: AppTextStyles.bodyStrong),
            servicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(friendlyError(e, context.l10n)),
              data: (services) {
                final active = services.where((s) => s.active).toList();
                final customerPackagesAsync = _customerId == null
                    ? null
                    : ref.watch(customerPackagesForCustomerProvider(_customerId!));
                return Column(
                  children: [
                    for (final s in active) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selectedServiceIds.contains(s.id),
                        title: Text(s.name),
                        subtitle: Text(
                          '${s.durationMinutes} min · ${formatMoney(s.price)}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            _selectedServiceIds.add(s.id);
                          } else {
                            _selectedServiceIds.remove(s.id);
                            _entitlementByService.remove(s.id);
                          }
                        }),
                      ),
                      if (_selectedServiceIds.contains(s.id) && customerPackagesAsync != null)
                        customerPackagesAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, _) => const SizedBox.shrink(),
                          data: (customerPackages) {
                            final eligible = _eligibleEntitlements(customerPackages, s.id);
                            if (eligible.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(
                                left: AppSpacing.xl,
                                bottom: AppSpacing.sm,
                              ),
                              child: DropdownButtonFormField<String?>(
                                initialValue: _entitlementByService[s.id],
                                isDense: true,
                                decoration: InputDecoration(
                                  labelText: context.l10n.pkgUseEntitlementLabel,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text(context.l10n.pkgPayNormally),
                                  ),
                                  for (final e in eligible)
                                    DropdownMenuItem(
                                      value: e.id,
                                      child: Text(
                                        context.l10n.pkgEntitlementOption(
                                          e.remainingSessions,
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() {
                                  if (v == null) {
                                    _entitlementByService.remove(s.id);
                                  } else {
                                    _entitlementByService[s.id] = v;
                                  }
                                }),
                              ),
                            );
                          },
                        ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: context.l10n.apptNotesOptionalLabel,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: context.l10n.apptBookTitle,
                      onPressed: _staffId == null
                          ? null
                          : () => _submit(active),
                      loading: _loading,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
