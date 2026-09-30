import 'package:brewflow_pos/app/navigation/navigation_config.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher_widget.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
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
/// The rail starts open on every app entry and auto-collapses after the FIRST
/// app-level navigation on any width >= 600 (tablet compact and wide desktop
/// alike — no width-band thresholds) so the opened page gets the full width.
/// It stays collapsed through subsequent navigations until reopened via the
/// floating menu toggle. The collapse lives in [navRailCollapsedProvider] so
/// it survives shell remounts: pushed top-level pages such as /closing and
/// /staff/payroll replace the shell's route match while open, and the shell
/// must come back collapsed on return.
///
/// Content comes from the router's [StatefulNavigationShell]; destinations
/// switch with goBranch so pages stay alive between navigation (no route
/// recreation). Logout uses the single existing AuthController flow.
///
/// Permission awareness: for a resolved STAFF profile the destination list is
/// filtered to the granted modules (the router guard remains the hard
/// boundary — hidden entries alone are never the enforcement). OWNER and
/// unresolved sessions render every destination.
///
/// Owner customization: the display order and the phone main-bar split come
/// from the persisted [NavArrangement]. It is applied BEFORE the permission
/// filter, so it can only reorganize what is already reachable — it never
/// hides, disables, deletes or revokes a feature, and never grants access.
/// Destination labels stay canonical and are never affected by it.
/// ---------------------------------------------------------------------------

final class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const double _navigationBreakpoint = 600;
  static const double _extendedSidebarBreakpoint = 1000;

  /// Nav entries derived from the canonical [navDestinations] registry (label
  /// + icon pair), in branch order.
  ///
  /// Never hand-maintained: the registry is the single source of truth for the
  /// label, the icons AND the required permission of every destination. A
  /// hand-written list next to the router's branch list is what let the two
  /// drift apart and send the "Staff" entry to Stock.
  static final List<AppNavItem> _navItems = [
    for (final destination in navDestinations)
      AppNavItem(
        label: destination.label,
        icon: destination.icon,
        selectedIcon: destination.selectedIcon,
      ),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// Shared navigation-rail collapsed state for the app shell.
///
/// Provider-level (not widget state) so it survives shell remounts: pushed
/// top-level pages like /closing and /staff/payroll replace the shell's route
/// match while open, and a fresh shell must come back collapsed, not reopened.
final class NavRailCollapsed extends Notifier<bool> {
  @override
  bool build() => false;

  /// Auto-hide the rail after an app-level navigation (>= 600 width).
  void collapse() => state = true;

  /// Restore the rail via the floating menu toggle.
  void reopen() => state = false;
}

final navRailCollapsedProvider = NotifierProvider<NavRailCollapsed, bool>(
  NavRailCollapsed.new,
);

final class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  /// Branch the shell already auto-redirected to; prevents re-scheduling the
  /// same navigation on every build while the branch index settles.
  int? _lastAutoRedirectBranch;

  /// Set once when a staff profile grants no shell branch at all — the shell
  /// then hands over to /no-access instead of rendering an empty navigation.
  bool _redirectedToNoAccess = false;

  /// The router's route-information source, listened to for location changes.
  /// Every app-level nav (rail taps, context.go quick actions, deep links,
  /// sub-page pushes) surfaces here once, matching any navigation trigger.
  late final RouteInformationProvider _routeInfo;

  /// The location the shell mounted at. The first REAL change after that
  /// collapses the rail on widths >= 600; same-location re-navigations (e.g.
  /// re-selecting the active branch) never collapse.
  String? _lastNavLocation;

  /// Shell body width from the most recent [LayoutBuilder] layout — the
  /// single source for the tablet/desktop decision. Navigation never resizes
  /// the window, so the route listener safely reuses this instead of reading
  /// MediaQuery independently.
  double _layoutWidth = AppShell._extendedSidebarBreakpoint;

  @override
  void initState() {
    super.initState();
    final router = ref.read(appRouterProvider);
    _routeInfo = router.routeInformationProvider;
    // Baseline the location AFTER the first frame: around mount, go_router
    // re-reports the startup/redirect location (and tearing down a previous
    // scope may emit one last value). All of that is startup noise — only a
    // real navigation after the shell settles may collapse the rail.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastNavLocation = _routeInfo.value.uri.toString();
    });
    _routeInfo.addListener(_handleRouteChange);
    // When the signed-in staff profile's grants change (e.g. an owner re-saves
    // permissions, or a staff profile arrives while the app is running), never
    // leave the user on a branch their grants hide: land on the first allowed
    // destination instead. One-shot per target — the route guard independently
    // denies direct navigation.
    ref.listenManual(userProfileProvider, (previous, next) {
      if (!next.hasValue || next.value == null) return;
      if (next.value!.role != UserRole.staff) return;
      _redirectAwayFromHiddenBranch();
    });
  }

  @override
  void dispose() {
    _routeInfo.removeListener(_handleRouteChange);
    super.dispose();
  }

  /// Collapse trigger for the auto-hide rail — the single mechanism for every
  /// navigation type and both non-phone widths (no threshold-skipping):
  ///
  /// The value the shell settles on after its first frame is the baseline
  /// (cold start stays open). Any subsequent location change while the shell
  /// renders at >= 600 collapses the shared rail so the opened page reclaims
  /// the full width. Phone (< 600) keeps its fixed bottom navigation and never
  /// collapses.
  void _handleRouteChange() {
    if (!mounted) return;
    final current = _routeInfo.value.uri.toString();
    // No settled baseline yet (mount/startup frame): record and never collapse
    // — this absorbs redirect/teardown noise around shell creation.
    if (_lastNavLocation == null) {
      _lastNavLocation = current;
      return;
    }
    if (current == _lastNavLocation) return;
    _lastNavLocation = current;
    if (_layoutWidth >= AppShell._navigationBreakpoint) {
      ref.read(navRailCollapsedProvider.notifier).collapse();
    }
  }

  /// Branches the current session may open, in the owner's customized order.
  ///
  /// Reads the permission straight off the canonical registry, so the
  /// authorization boundary and the navigation list can never disagree. The
  /// router guard stays the hard boundary — this only decides what is shown.
  List<int> _allowedBranches(WidgetRef ref) {
    final authorization = ref.read(authorizationProvider);
    final arrangement = NavArrangement.fromSettings(
      ref.read(shopSettingsProvider).value,
    );
    return [
      for (final route in arrangement.order)
        if (AppRoutes.branchIndexOf(route) >= 0)
          if (_granted(authorization, route)) AppRoutes.branchIndexOf(route),
    ];
  }

  bool _granted(AuthorizationService authorization, String route) {
    final permission = NavArrangement.permissionOfRoute(route);
    return permission == null || authorization.can(permission);
  }

  void _redirectAwayFromHiddenBranch() {
    final visible = _allowedBranches(ref);
    if (visible.isEmpty || visible.contains(navigationShell.currentIndex)) {
      return;
    }
    final target = visible.first;
    if (target == _lastAutoRedirectBranch) return;
    _lastAutoRedirectBranch = target;
    Future.microtask(
      () => navigationShell.goBranch(target, initialLocation: false),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    var items = AppShell._navItems;
    // The owner's navigation organization: display order plus the phone
    // main-bar split. Applied BEFORE the permission filter and never widening
    // it, so it can only reorganize what the session may already open.
    final arrangement = NavArrangement.fromSettings(
      ref.watch(shopSettingsProvider).value,
    );

    // `visible` maps a RENDERED destination position to its router branch.
    // It is always built in the owner's order, so the highlight must be
    // resolved through this map — a raw branch index would drift onto
    // whichever module happens to sit there once the order is customized or
    // the staff list is filtered.
    final currentBranch = navigationShell.currentIndex;
    var visible = [
      for (final route in arrangement.order) AppRoutes.branchIndexOf(route),
    ];
    if (filterActive) {
      final allowed = _allowedBranches(ref).toSet();
      visible = [
        for (final branch in visible)
          if (allowed.contains(branch)) branch,
      ];
    }
    items = [for (final branch in visible) AppShell._navItems[branch]];
    var selected = visible.indexOf(currentBranch);

    if (items.isEmpty) {
      // No shell destination granted: keep the navigation structurally safe
      // and hand over to /no-access (one-shot) — an empty selection index
      // cannot be rendered.
      items = AppShell._navItems;
      visible = List<int>.generate(items.length, (index) => index);
      if (!_redirectedToNoAccess) {
        _redirectedToNoAccess = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(AppRoutes.noAccess);
        });
      }
      selected = 0;
    } else if (selected < 0) {
      // Current branch is hidden for this profile: display-highlight the
      // first allowed destination while the profile change handler lands
      // there (this build only — no navigation here).
      selected = 0;
      if (filterActive) _redirectAwayFromHiddenBranch();
    }

    // Rendered positions that sit in the phone main bar; the rest go to the
    // "More" sheet. Derived from the arrangement, never from fixed indices.
    final primaryRoutes = arrangement.primary.toSet();
    final primaryIndices = [
      for (var i = 0; i < visible.length; i++)
        if (primaryRoutes.contains(AppRoutes.destinations[visible[i]])) i,
    ];

    void goTo(int index) {
      final branch = visible[index];
      navigationShell.goBranch(
        branch,
        initialLocation: branch == navigationShell.currentIndex,
      );
      // The auto-hide runs in the route listener above — one mechanism covers
      // rail taps and every other navigation source alike.
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutWidth = constraints.maxWidth;
        if (constraints.maxWidth < AppShell._navigationBreakpoint) {
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
            body: Column(
              children: [
                const ConnectivityBanner(),
                Expanded(child: navigationShell),
              ],
            ),
            // Deliberately NOT wrapped in SafeArea. This slot receives the
            // untouched bottom inset from the Scaffold, and NavigationBar's own
            // SafeArea applies it exactly once. A second wrapper here would
            // double-pad the bar on every edge-to-edge device.
            bottomNavigationBar: AppBottomNavigation(
              items: items,
              primaryIndices: primaryIndices,
              selectedIndex: selected.clamp(0, items.length - 1),
              onDestinationSelected: goTo,
            ),
          );
        }
        final extended =
            constraints.maxWidth >= AppShell._extendedSidebarBreakpoint;
        final collapsed = ref.watch(navRailCollapsedProvider);
        final settings = ref.watch(shopSettingsProvider).value;
        final appDisplayName = settings?.appDisplayName;
        final shopName = settings?.shopName;

        Widget sidebarFooter() => Column(
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
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            if (!extended) const Center(child: SyncStatusDot(onDark: true)),
            if (!extended) const SizedBox(height: AppSpacing.sm),
            const _SidebarLogout(),
          ],
        );

        Widget sidebar({required bool compact}) => AppSidebar(
          items: items,
          selectedIndex: selected.clamp(0, items.length - 1),
          extended: !compact,
          // Active business identity from Settings — the sidebar always names
          // the shop and app being operated, never a hardcoded brand.
          shopName: shopName,
          appDisplayName: appDisplayName,
          onDestinationSelected: goTo,
          footer: sidebarFooter(),
        );

        // Non-phone body: a compact rail on tablet (600..999) or an extended
        // sidebar at wide desktop (>= 1000). After any app-level navigation the
        // shared state collapses the rail on BOTH widths — one contract, no
        // threshold-skipping — so the opened page gets the full width. A
        // floating menu toggle (with sign-out beside it, still one tap away)
        // reopens the navigation whenever the operator wants it back.
        //
        // While collapsed, a reserved gutter (the width of the collapsed rail
        // slot) keeps page content clear of the floating controls at the top
        // left corner, and pages can adapt their own layout via
        // [TabletNavScope.isCollapsed].
        //
        // Billing/POS reclaims that gutter: its vertical category rail already
        // owns the navigation-side inset, so stacking both would squeeze the
        // shelf. Other destinations keep the gutter.
        final isBillingBranch =
            currentBranch == AppRoutes.branchIndexOf(AppRoutes.billing);
        Widget tabletBody() => Stack(
          children: [
            Row(
              children: [
                if (!collapsed) sidebar(compact: true),
                Expanded(
                  child: TabletNavScope(
                    collapsed: collapsed,
                    child: Padding(
                      padding: collapsed && !isBillingBranch
                          // 64 = compact rail slot (sm + 48 icon + sm); the
                          // gutter reads as a consistent content inset on every
                          // page, never matching the floating controls.
                          ? const EdgeInsets.only(left: AppSpacing.ultra)
                          : EdgeInsets.zero,
                      child: navigationShell,
                    ),
                  ),
                ),
              ],
            ),
            if (collapsed)
              Positioned(
                left: AppSpacing.sm,
                top: AppSpacing.sm,
                child: SafeArea(
                  top: false,
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NavToggle(
                        onPressed: () => ref
                            .read(navRailCollapsedProvider.notifier)
                            .reopen(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _SidebarLogout(),
                    ],
                  ),
                ),
              ),
          ],
        );

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const ConnectivityBanner(),
                Expanded(
                  // The extended desktop rail stays put while open; when the
                  // shell is collapsed (or on tablet) render the collapse-aware
                  // body regardless of the current width band — the floating
                  // toggle, gutter and TabletNavScope work everywhere >= 600.
                  child: !collapsed && extended
                      ? Row(
                          children: [
                            sidebar(compact: false),
                            Expanded(child: navigationShell),
                          ],
                        )
                      : tabletBody(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Floating control shown on non-phone widths while the navigation rail is
/// auto-hidden: reopening it returns the rail (and its sign-out).
final class _NavToggle extends StatelessWidget {
  const _NavToggle({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: const BoxDecoration(
          color: AppColors.primaryDark,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          tooltip: 'Open navigation',
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
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
///
/// Every vertical dimension here is a fixed constant rather than a result of
/// the title's intrinsic content. [AppBar] sizes itself from its toolbar child
/// (`height = topInset + max(0, toolbarHeight - childHeight) + childHeight`), so
/// a title whose height came from font metrics or a [DropdownButton]'s intrinsic
/// size made the whole header drift with the device's font and layout. Pinning
/// both the toolbar and the title stack keeps the header identical on Android
/// 14, 15 and 16, and keeps it in step with [preferredSize] so the Scaffold
/// never reserves more room than the bar actually paints.
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

  /// Owner header: app name + shop name + business switcher.
  static const double ownerToolbarHeight = 112;

  /// Deterministic height of the owner title stack. The content it holds is
  /// 18 (app name) + 1 + 16 (shop name) + 4 + [BusinessSwitcher]'s 40dp control
  /// = 79, so this leaves a few dp of slack inside [ownerToolbarHeight] rather
  /// than sizing itself to whichever font the device resolves.
  static const double ownerTitleHeight = 84;

  /// Staff header: the same stack without the switcher (18 + 1 + 16 = 35).
  static const double compactToolbarHeight = 64;
  static const double compactTitleHeight = 40;

  @override
  Size get preferredSize =>
      Size.fromHeight(showSwitcher ? ownerToolbarHeight : compactToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final displayName = appDisplayName?.trim().isNotEmpty ?? false
        ? appDisplayName!.trim()
        : AppConstants.defaultAppDisplayName;
    final toolbarHeight = showSwitcher
        ? ownerToolbarHeight
        : compactToolbarHeight;
    final titleHeight = showSwitcher ? ownerTitleHeight : compactTitleHeight;
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Paired with [preferredSize] so the reserved height and the painted
      // height are the same number, and the title stack below always has room.
      toolbarHeight: toolbarHeight,
      backgroundColor: appColors.background,
      surfaceTintColor: Colors.transparent,
      titleSpacing: AppSpacing.lg,
      // The fixed height is the whole point: the Column fills it instead of
      // hugging its children, so nothing in the stack can push the header
      // taller on a device with different font metrics.
      title: SizedBox(
        height: titleHeight,
        child: Row(
          children: [
            const BrandMark(size: BrandMark.compactSize),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
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
                      child: BusinessSwitcher(compact: true, dropdown: true),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
      content: const Text('Are you sure you want to sign out?'),
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
  final connectivity = ref.read(connectivityServiceProvider);
  return switch (connectivity.status) {
    ConnectivityStatus.online => 'Online',
    ConnectivityStatus.disconnected => 'Offline',
    ConnectivityStatus.unknown => 'Connecting…',
  };
}
