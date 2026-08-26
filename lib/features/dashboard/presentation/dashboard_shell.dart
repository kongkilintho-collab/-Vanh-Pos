import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/business_role.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/business_context_provider.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final BusinessRole minRole;
  final bool implemented;

  const _NavItem({
    required this.icon,
    required this.label,
    this.minRole = BusinessRole.staff,
    this.implemented = false,
  });
}

const _navItems = [
  _NavItem(icon: Icons.dashboard_outlined, label: 'Overview', implemented: true),
  _NavItem(icon: Icons.point_of_sale_outlined, label: 'POS', minRole: BusinessRole.cashier),
  _NavItem(icon: Icons.groups_outlined, label: 'Customers', minRole: BusinessRole.cashier),
  _NavItem(icon: Icons.spa_outlined, label: 'Services', minRole: BusinessRole.manager),
  _NavItem(icon: Icons.inventory_2_outlined, label: 'Products', minRole: BusinessRole.manager),
  _NavItem(icon: Icons.warehouse_outlined, label: 'Inventory', minRole: BusinessRole.manager),
  _NavItem(icon: Icons.badge_outlined, label: 'Staff', minRole: BusinessRole.admin),
  _NavItem(icon: Icons.percent_outlined, label: 'Commissions', minRole: BusinessRole.manager),
  _NavItem(icon: Icons.receipt_long_outlined, label: 'Expenses', minRole: BusinessRole.admin),
  _NavItem(icon: Icons.bar_chart_outlined, label: 'Reports', minRole: BusinessRole.manager),
  _NavItem(icon: Icons.settings_outlined, label: 'Settings', minRole: BusinessRole.admin),
];

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider);
    final user = ref.watch(currentUserProvider);

    if (membership == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final visibleItems =
        _navItems.where((item) => membership.role.isAtLeast(item.minRole)).toList();
    if (_selectedIndex >= visibleItems.length) _selectedIndex = 0;

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final sidebar = _Sidebar(
      items: visibleItems,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      businessName: membership.business.name,
      roleLabel: membership.role.label,
      userEmail: user?.email ?? '',
    );

    final content = _OverviewContent(
      selectedLabel: visibleItems[_selectedIndex].label,
      implemented: visibleItems[_selectedIndex].implemented,
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 260, child: sidebar),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(visibleItems[_selectedIndex].label)),
      drawer: Drawer(child: sidebar),
      body: content,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String businessName;
  final String roleLabel;
  final String userEmail;

  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.businessName,
    required this.roleLabel,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Theme.of(context).cardTheme.color,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      businessName.isNotEmpty ? businessName[0].toUpperCase() : '?',
                      style: AppTextStyles.subtitle.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      businessName,
                      style: AppTextStyles.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = index == selectedIndex;
                  return ListTile(
                    leading: Icon(item.icon, size: 20),
                    title: Text(item.label, style: AppTextStyles.body),
                    trailing: item.implemented
                        ? null
                        : Text('Soon', style: AppTextStyles.caption.copyWith(color: AppColors.muted)),
                    selected: selected,
                    selectedTileColor: AppColors.primaryLight.withValues(alpha: 0.5),
                    onTap: () {
                      onSelect(index);
                      if (Scaffold.of(context).isDrawerOpen) Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(userEmail, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
                        Text(roleLabel, style: AppTextStyles.captionStrong.copyWith(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout, size: 18),
                    onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewContent extends StatelessWidget {
  final String selectedLabel;
  final bool implemented;

  const _OverviewContent({required this.selectedLabel, required this.implemented});

  @override
  Widget build(BuildContext context) {
    if (!implemented) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_outlined, size: 40, color: AppColors.muted),
              const SizedBox(height: AppSpacing.md),
              Text('$selectedLabel is not built yet', style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This section is scheduled later in the build plan.',
                style: AppTextStyles.body.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: AppTextStyles.displayMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "You're authenticated and your business workspace is set up. "
            'POS, customers, inventory, and reporting come online as each '
            'part of the build lands.',
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
