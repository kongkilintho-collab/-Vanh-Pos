import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../shared/models/business_role.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../audit/presentation/audit_log_screen.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../../commissions/presentation/commissions_screen.dart';
import '../../customers/presentation/customers_screen.dart';
import '../../expenses/presentation/expenses_screen.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../pos/presentation/pos_screen.dart';
import '../../products/presentation/products_screen.dart';
import '../../reports/presentation/dashboard_overview_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../sales/presentation/sales_screen.dart';
import '../../services/presentation/services_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../staff/presentation/staff_screen.dart';

class _NavItem {
  final IconData icon;
  final String id;
  final BusinessRole minRole;
  final bool implemented;

  const _NavItem({
    required this.icon,
    required this.id,
    this.minRole = BusinessRole.staff,
    this.implemented = false,
  });

  String label(AppLocalizations l10n) => switch (id) {
    'overview' => l10n.navOverview,
    'pos' => l10n.navPos,
    'sales' => l10n.navSales,
    'customers' => l10n.navCustomers,
    'services' => l10n.navServices,
    'products' => l10n.navProducts,
    'inventory' => l10n.navInventory,
    'staff' => l10n.navStaff,
    'commissions' => l10n.navCommissions,
    'expenses' => l10n.navExpenses,
    'reports' => l10n.navReports,
    'auditLog' => l10n.navAuditLog,
    'settings' => l10n.navSettings,
    _ => id,
  };
}

const _navItems = [
  _NavItem(icon: Icons.dashboard_outlined, id: 'overview', implemented: true),
  _NavItem(
    icon: Icons.point_of_sale_outlined,
    id: 'pos',
    minRole: BusinessRole.cashier,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.receipt_outlined,
    id: 'sales',
    minRole: BusinessRole.cashier,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.groups_outlined,
    id: 'customers',
    minRole: BusinessRole.cashier,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.spa_outlined,
    id: 'services',
    minRole: BusinessRole.manager,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.inventory_2_outlined,
    id: 'products',
    minRole: BusinessRole.manager,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.warehouse_outlined,
    id: 'inventory',
    minRole: BusinessRole.manager,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.badge_outlined,
    id: 'staff',
    minRole: BusinessRole.admin,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.percent_outlined,
    id: 'commissions',
    minRole: BusinessRole.manager,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.receipt_long_outlined,
    id: 'expenses',
    minRole: BusinessRole.admin,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.bar_chart_outlined,
    id: 'reports',
    minRole: BusinessRole.manager,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.history_outlined,
    id: 'auditLog',
    minRole: BusinessRole.admin,
    implemented: true,
  ),
  _NavItem(
    icon: Icons.settings_outlined,
    id: 'settings',
    minRole: BusinessRole.admin,
    implemented: true,
  ),
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

    final visibleItems = _navItems
        .where((item) => membership.role.isAtLeast(item.minRole))
        .toList();
    if (_selectedIndex >= visibleItems.length) _selectedIndex = 0;

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final sidebar = _Sidebar(
      items: visibleItems,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      businessName: membership.business.name,
      roleLabel: membership.role.label(context.l10n),
      userEmail: user?.email ?? '',
    );

    final content = _buildContent(visibleItems[_selectedIndex]);

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
      appBar: AppBar(
        title: Text(visibleItems[_selectedIndex].label(context.l10n)),
      ),
      drawer: Drawer(child: sidebar),
      body: content,
    );
  }

  Widget _buildContent(_NavItem item) {
    switch (item.id) {
      case 'pos':
        return const PosScreen();
      case 'sales':
        return const SalesScreen();
      case 'services':
        return const ServicesScreen();
      case 'products':
        return const ProductsScreen();
      case 'customers':
        return const CustomersScreen();
      case 'staff':
        return const StaffScreen();
      case 'commissions':
        return const CommissionsScreen();
      case 'inventory':
        return const InventoryScreen();
      case 'expenses':
        return const ExpensesScreen();
      case 'overview':
        return const DashboardOverviewScreen();
      case 'reports':
        return const ReportsScreen();
      case 'auditLog':
        return const AuditLogScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return _OverviewContent(item: item);
    }
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
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
                      businessName.isNotEmpty
                          ? businessName[0].toUpperCase()
                          : '?',
                      style: AppTextStyles.subtitle.copyWith(
                        color: Colors.white,
                      ),
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
                    title: Text(
                      item.label(context.l10n),
                      style: AppTextStyles.body,
                    ),
                    trailing: item.implemented
                        ? null
                        : Text(
                            context.l10n.navSoon,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                    selected: selected,
                    selectedTileColor: AppColors.primaryLight.withValues(
                      alpha: 0.5,
                    ),
                    onTap: () {
                      onSelect(index);
                      if (Scaffold.of(context).isDrawerOpen)
                        Navigator.of(context).pop();
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
                        Text(
                          userEmail,
                          style: AppTextStyles.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          roleLabel,
                          style: AppTextStyles.captionStrong.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.authSignOut,
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
  final _NavItem item;

  const _OverviewContent({required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.implemented) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_outlined,
                size: 40,
                color: AppColors.muted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.navNotBuiltYet(item.label(context.l10n)),
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.navScheduledLater,
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
          Text(context.l10n.navOverview, style: AppTextStyles.displayMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.overviewIntro,
            style: AppTextStyles.body.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
