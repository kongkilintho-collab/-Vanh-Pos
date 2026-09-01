import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'auth_providers.dart';
import '../../../l10n/l10n_extensions.dart';

/// Shown after sign-up (or sign-in) when the user has no business
/// membership yet. Creating a business makes them its OWNER.
class OnboardingCreateBusinessScreen extends ConsumerStatefulWidget {
  const OnboardingCreateBusinessScreen({super.key});

  @override
  ConsumerState<OnboardingCreateBusinessScreen> createState() =>
      _OnboardingCreateBusinessScreenState();
}

class _OnboardingCreateBusinessScreenState
    extends ConsumerState<OnboardingCreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(businessRepositoryProvider)
          .createBusiness(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
          );
      ref.invalidate(myMembershipsProvider);
      // HomeGate rebuilds once myMembershipsProvider resolves and routes
      // to the dashboard automatically.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e, context.l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => ref.read(authRepositoryProvider).signOut(),
            child: Text(context.l10n.authSignOut),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.authSetUpBusinessTitle,
                    style: AppTextStyles.displayMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.authSetUpBusinessSubtitle,
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.authBusinessNameLabel,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.l10n.authBusinessNameRequired
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.l10n.authPhoneOptionalLabel,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: context.l10n.authCreateBusiness,
                    onPressed: _submit,
                    loading: _loading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
