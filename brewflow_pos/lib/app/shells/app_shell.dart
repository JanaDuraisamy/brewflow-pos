import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher_widget.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Application Shell
///
/// The authenticated main layout hosting every business destination. One
/// shell, three responsive modes driven by the design-system navigation:
/// - mobile (< 600): compact AppBar + [AppBottomNavigation]
/// - tablet (>= 600): compact [AppSidebar] rail
/// - wide desktop (>= 1000): extended [AppSidebar] with brand labels
///
/// Content comes from the router's [StatefulNavigationShell]; destinations
/// switch with goBranch so pages stay alive between navigation (no route
/// recreation). Logout uses the single existing AuthController flow.
///
/// Permission awareness: for a resolved STAFF profile the destination list is
/// filtered to the granted modules (the router guard remains the hard
/// boundary — hidden entries alone are never the enforcement). OWNER and
/// unresolved sessions render the full, original navigation unchanged.
/// ---------------------------------------------------------------------------

final class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const double _navigationBreakpoint = 600;
  static const double _extendedSidebarBreakpoint = 1000;

  /// Branch order MUST match AppRoutes.destinations / router branches.
  static const List<AppNavItem> _navItems = [
    AppNavItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    AppNavItem(
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
    AppNavItem(
      label: 'Billing',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale,
    ),
    AppNavItem(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    AppNavItem(
      label: 'Customers',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    AppNavItem(
      label: 'Suppliers',
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping,
    ),
    AppNavItem(
      label: 'Purchases',
      icon: Icons.shopping_basket_outlined,
      selectedIcon: Icons.shopping_basket,
    ),
    AppNavItem(
      label: 'Expenses',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments,
    ),
    AppNavItem(
      label: 'Reports',
      icon: Icons.insert_chart_outlined,
      selectedIcon: Icons.insert_chart,
    ),
    AppNavItem(
      label: 'Offers',
      icon: Icons.local_offer_outlined,
      selectedIcon: Icons.local_offer,
    ),
    AppNavItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  /// Required permission per branch index (aligned with [_navItems]).
  static const List<Permission> _navPermissions = [
    Permission.viewDashboard,
    Permission.viewInventory,
    Permission.billing,
    Permission.orders,
    Permission.customers,
    Permission.suppliers,
    Permission.purchases,
    Permission.expenses,
    Permission.reports,
    Permission.offers,
    Permission.settings,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final filterActive = profile != null && profile.role == UserRole.staff;
    // Staff tablets are single-business: never keep Combined selection.
    if (filterActive &&
        ref.watch(businessSwitcherProvider) == BusinessContext.all) {
      Future.microtask(
        () => ref
            .read(businessSwitcherProvider.notifier)
            .select(BusinessContext.cafe),
      );
    }

    var items = _navItems;
    var selected = navigationShell.currentIndex;
    var visible = List<int>.generate(_navItems.length, (index) => index);
    if (filterActive) {
      final authorization = ref.watch(authorizationProvider);
      visible = [
        for (var i = 0; i < _navItems.length; i++)
          if (authorization.can(_navPermissions[i])) i,
      ];
      items = [for (final i in visible) _navItems[i]];
      // Highlight the first allowed entry when the current branch is hidden;
      // the content itself is redirected by the route guard.
      if (!visible.contains(selected)) {
        selected = 0;
      }
    }

    void goTo(int index) {
      final branch = filterActive ? visible[index] : index;
      navigationShell.goBranch(
        branch,
        initialLocation: branch == navigationShell.currentIndex,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _navigationBreakpoint) {
          return Scaffold(
            appBar: _MobileAppBar(
              appDisplayName: ref
                  .watch(shopSettingsProvider)
                  .value
                  ?.appDisplayName,
              shopName: ref.watch(shopSettingsProvider).value?.shopName,
              // The business switcher is Owner-only. Staff tablets stay fixed
              // to one assigned shop with no switcher and no Combined view.
              showSwitcher: !filterActive,
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(child: navigationShell),
                  SafeArea(
                    top: false,
                    child: AppBottomNavigation(
                      items: items,
                      selectedIndex: selected.clamp(0, items.length - 1),
                      onDestinationSelected: goTo,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final extended = constraints.maxWidth >= _extendedSidebarBreakpoint;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                AppSidebar(
                  items: items,
                  selectedIndex: selected.clamp(0, items.length - 1),
                  extended: extended,
                  // Active business identity from Settings — the sidebar
                  // always names the shop being operated, never a hardcoded
                  // brand.
                  shopName: ref.watch(shopSettingsProvider).value?.shopName,
                  onDestinationSelected: goTo,
                  footer: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Owner-only business switcher in the extended sidebar.
                      if (!filterActive && extended) ...[
                        const Padding(
                          padding: EdgeInsets.only(
                            bottom: AppSpacing.sm,
                            left: AppSpacing.xs,
                            right: AppSpacing.xs,
                          ),
                          child: BusinessSwitcher(compact: true),
                        ),
                      ],
                      if (extended)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SyncStatusDot(onDark: true),
                              const SizedBox(width: 6),
                              Text(
                                _syncLabel(ref),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      if (!extended)
                        const Center(child: SyncStatusDot(onDark: true)),
                      if (!extended) const SizedBox(height: AppSpacing.sm),
                      const _SidebarLogout(),
                    ],
                  ),
                ),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _SidebarLogout extends ConsumerWidget {
  const _SidebarLogout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: const Icon(Icons.logout_outlined, color: Colors.white70),
        tooltip: 'Sign out',
        onPressed: () => _confirmSignOut(context, ref),
      ),
    );
  }
}

/// Lightweight phone header — compact brand wordmark, a subtle sync dot and a
/// single sign-out action. The sync readout is intentionally faint here; the
/// full sync card lives on the Dashboard where there is room to explain state.
final class _MobileAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const _MobileAppBar({
    this.appDisplayName,
    this.shopName,
    this.showSwitcher = false,
  });

  final String? appDisplayName;
  final String? shopName;

  /// Owner-only: renders the business switcher below the shop name.
  final bool showSwitcher;

  @override
  Size get preferredSize => Size.fromHeight(showSwitcher ? 112 : 64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final displayName = appDisplayName?.trim().isNotEmpty ?? false
        ? appDisplayName!.trim()
        : AppConstants.defaultAppDisplayName;
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: appColors.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: AppSpacing.lg,
      title: Row(
        children: [
          const BrandMark(size: BrandMark.compactSize),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: appColors.charcoal,
                    height: 1.1,
                  ),
                ),
                if (shopName != null && shopName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    shopName!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (showSwitcher) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BusinessSwitcher(compact: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        const Center(child: SyncStatusDot()),
        const SizedBox(width: AppSpacing.xs),
        _LogoutIconButton(),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

final class _LogoutIconButton extends ConsumerWidget {
  const _LogoutIconButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout_outlined),
      tooltip: 'Sign out',
      onPressed: () => _confirmSignOut(context, ref),
    );
  }
}

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out'),
      content: const Text(
        'Are you sure you want to sign out? '
        'Any unsynced data will remain on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    ref.read(authControllerProvider.notifier).signOut();
  }
}

String _syncLabel(WidgetRef ref) {
  final status = ref.read(syncStatusProvider);
  if (status.isSyncing) return 'Syncing…';
  switch (status.level) {
    case SyncStatusLevel.synced:
      return 'Synced';
    case SyncStatusLevel.pending:
      return '${status.pendingCount} pending';
    case SyncStatusLevel.offline:
      return 'Offline';
    case SyncStatusLevel.unconfirmed:
      return 'Connecting…';
    case SyncStatusLevel.idle:
      return '';
    case SyncStatusLevel.syncing:
      return 'Syncing…';
    case SyncStatusLevel.error:
      return 'Sync failed';
  }
}
