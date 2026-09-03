import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import 'cart_controller.dart';
import 'cart_panel.dart';
import 'deposit_checkout_sheet.dart';
import 'item_picker.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    if (isWide) {
      return const Row(
        children: [
          Expanded(flex: 3, child: ItemPicker()),
          VerticalDivider(width: 1),
          SizedBox(
            width: 380,
            child: Column(
              children: [_DepositBar(), Expanded(child: CartPanel())],
            ),
          ),
        ],
      );
    }

    return const Stack(
      children: [
        ItemPicker(),
        Align(alignment: Alignment.bottomCenter, child: _CartBar()),
      ],
    );
  }
}

/// Phase 3 (Deposit / Outstanding Balance): the explicit "Accept deposit"
/// entry point, kept deliberately separate from CartPanel's own "Complete
/// sale" button (which stays full-payment-only, byte-for-byte unchanged) --
/// a cashier must take a distinct, differently-labeled action to start a
/// partial-payment sale, so it can never be triggered by accident.
class _DepositBar extends ConsumerWidget {
  const _DepositBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
      ),
      child: OutlinedButton.icon(
        onPressed: cart.isEmpty ? null : () => showDepositCheckoutSheet(context),
        icon: const Icon(Icons.savings_outlined, size: 18),
        label: Text(context.l10n.posAcceptDepositAction),
      ),
    );
  }
}

class _CartBar extends ConsumerWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final itemCount = cart.lines.fold<int>(0, (sum, l) => sum + l.quantity);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const SizedBox(
                height: 640,
                child: Column(
                  children: [_DepositBar(), Expanded(child: CartPanel())],
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Text(
                    context.l10n.posCartItemCount(itemCount),
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(cart.total),
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                    size: 18,
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
