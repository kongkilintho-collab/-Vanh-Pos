import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/onboarding_create_business_screen.dart';
import 'dashboard_shell.dart';
import '../../../l10n/l10n_extensions.dart';

/// Decides, once signed in, whether the user lands in onboarding (no
/// business yet) or the dashboard (has at least one active membership).
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membershipsAsync = ref.watch(myMembershipsProvider);

    return membershipsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorBanner(message: friendlyError(err, context.l10n)),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: context.l10n.commonRetry,
                  expand: false,
                  onPressed: () => ref.invalidate(myMembershipsProvider),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (memberships) {
        if (memberships.isEmpty) return const OnboardingCreateBusinessScreen();
        return const DashboardShell();
      },
    );
  }
}
