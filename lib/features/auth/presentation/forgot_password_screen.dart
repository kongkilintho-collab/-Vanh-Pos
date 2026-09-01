import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'auth_providers.dart';
import '../../../l10n/l10n_extensions.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
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
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
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
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _sent
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mark_email_read_outlined, size: 40),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        context.l10n.authCheckYourEmail,
                        style: AppTextStyles.headline,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.l10n.authResetLinkSentTo(
                          _emailController.text.trim(),
                        ),
                        style: AppTextStyles.body,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.authResetPasswordTitle,
                          style: AppTextStyles.displayMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          context.l10n.authResetPasswordSubtitle,
                          style: AppTextStyles.body,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: context.l10n.authEmailLabel,
                          ),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? context.l10n.authEmailInvalid
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        PrimaryButton(
                          label: context.l10n.authSendResetLink,
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
