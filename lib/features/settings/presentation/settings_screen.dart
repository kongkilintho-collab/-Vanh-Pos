import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../l10n/locale_provider.dart';
import '../../../shared/models/business.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/business_context_provider.dart';
import 'settings_providers.dart';

/// Business settings (F9-4). The dashboard's minRole: BusinessRole.admin
/// nav gate is a UX convenience only -- the actual security boundary is
/// update_business_settings' own has_role_at_least('ADMIN') check
/// (0028_business_settings_rpc.sql); a lower-ranked caller reaching this
/// screen by other means would simply have their save rejected there.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController();
  late final _phoneController = TextEditingController();
  late final _emailController = TextEditingController();
  late final _addressController = TextEditingController();
  late final _currencyController = TextEditingController();
  late final _taxRateController = TextEditingController();
  late final _logoUrlController = TextEditingController();
  bool _taxEnabled = false;
  bool _initialized = false;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _currencyController.dispose();
    _taxRateController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  void _populateFrom(Business business) {
    if (_initialized) return;
    _nameController.text = business.name;
    _phoneController.text = business.phone ?? '';
    _emailController.text = business.email ?? '';
    _addressController.text = business.address ?? '';
    _currencyController.text = business.currency;
    _taxRateController.text = business.taxRate.toString();
    _logoUrlController.text = business.logoUrl ?? '';
    _taxEnabled = business.taxEnabled;
    _initialized = true;
  }

  Future<void> _submit(String businessId) async {
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(businessRepositoryProvider)
          .updateSettings(
            businessId: businessId,
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            email: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            address: _addressController.text.trim().isEmpty
                ? null
                : _addressController.text.trim(),
            currency: _currencyController.text.trim().toUpperCase(),
            taxEnabled: _taxEnabled,
            taxRate: double.parse(_taxRateController.text.trim()),
            logoUrl: _logoUrlController.text.trim().isEmpty
                ? null
                : _logoUrlController.text.trim(),
          );
      ref.invalidate(myMembershipsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsSaved)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider);
    final canEdit = ref.watch(canEditBusinessSettingsProvider);

    if (membership == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _populateFrom(membership.business);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.settingsTitle,
                style: AppTextStyles.displayMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!canEdit)
                Text(
                  context.l10n.settingsReadOnlyNotice,
                  style: AppTextStyles.body.copyWith(color: AppColors.muted),
                ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _nameController,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsBusinessNameLabel,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.l10n.commonRequired
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneController,
                enabled: canEdit,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.l10n.authPhoneOptionalLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                enabled: canEdit,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.customersEmailOptionalLabel,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return v.contains('@') ? null : context.l10n.authEmailInvalid;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _addressController,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: context.l10n.customersAddressOptionalLabel,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _currencyController,
                enabled: canEdit,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsCurrencyCodeLabel,
                ),
                validator: (v) => (v == null || v.trim().length != 3)
                    ? context.l10n.settingsCurrencyCodeInvalid
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.settingsTaxEnabled),
                value: _taxEnabled,
                onChanged: canEdit
                    ? (v) => setState(() => _taxEnabled = v)
                    : null,
              ),
              TextFormField(
                controller: _taxRateController,
                enabled: canEdit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.settingsTaxRateLabel,
                ),
                validator: (v) {
                  final parsed = double.tryParse((v ?? '').trim());
                  if (parsed == null)
                    return context.l10n.settingsTaxRateInvalidNumber;
                  if (parsed < 0 || parsed > 100)
                    return context.l10n.settingsTaxRateRange;
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _logoUrlController,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsLogoUrlOptionalLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (canEdit)
                PrimaryButton(
                  label: context.l10n.commonSaveChanges,
                  onPressed: () => _submit(membership.business.id),
                  loading: _loading,
                  expand: false,
                ),
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                context.l10n.settingsLanguageTitle,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.settingsLanguageSubtitle,
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              const _LanguageSelector(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSelector extends ConsumerWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<Locale>(
        initialValue: locale,
        decoration: const InputDecoration(isDense: true),
        items: [
          DropdownMenuItem(
            value: const Locale('en'),
            child: Text(context.l10n.languageEnglish),
          ),
          DropdownMenuItem(
            value: const Locale('lo'),
            child: Text(context.l10n.languageLao),
          ),
        ],
        onChanged: (value) {
          if (value != null)
            ref.read(localeControllerProvider.notifier).setLocale(value);
        },
      ),
    );
  }
}
