import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../shared/models/customer.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'pos_providers.dart';
import '../../../l10n/l10n_extensions.dart';

Future<Customer?> showCustomerPickerSheet(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CustomerPickerSheet(),
  );
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  List<Customer>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null) return;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(posRepositoryProvider)
          .searchCustomers(businessId, query);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _quickCreate() async {
    final businessId = ref.read(currentMembershipProvider)?.business.id;
    if (businessId == null || _query.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final customer = await ref
          .read(posRepositoryProvider)
          .quickCreateCustomer(businessId: businessId, name: _query.trim());
      if (mounted) Navigator.of(context).pop(customer);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.posSelectCustomer,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: context.l10n.posSearchNameOrPhone,
                ),
                onChanged: _search,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ErrorBanner(message: _error!),
              Expanded(
                child: _loading && _results == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        children: [
                          for (final c in _results ?? const [])
                            ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline, size: 18),
                              ),
                              title: Text(c.name),
                              subtitle: c.phone != null ? Text(c.phone!) : null,
                              onTap: () => Navigator.of(context).pop(c),
                            ),
                          if ((_results ?? const []).isEmpty && !_loading)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                context.l10n.posNoCustomersFound,
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (_query.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: context.l10n.posCreateAsNewCustomer(_query.trim()),
                  onPressed: _quickCreate,
                  loading: _loading,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
