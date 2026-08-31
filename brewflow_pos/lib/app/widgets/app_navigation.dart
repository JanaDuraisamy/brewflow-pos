import 'package:brewflow_pos/app/widgets/brand_mark.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Navigation
///
/// - [AppNavItem]: one destination (label + icon pair).
/// - [AppBottomNavigation]: mobile bottom navigation bar with soft green
///   active indicator.
/// - [AppSidebar]: dark green vertical sidebar for tablet/desktop with the
///   BrewFlow brand on top, green highlighted active state and optional
///   footer (profile/actions area).
/// ---------------------------------------------------------------------------

final class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Mobile bottom navigation bar — phone-optimized, Apple-inspired.
///
/// On narrow phones (<600dp) the bar shows only the 5 most important
/// destinations; the rest live in a clean “More” sheet. This keeps labels
/// single-line at 411dp, avoids the 10-item wrap seen in the screenshots,
/// and feels premium — light, spacious, 56dp height, 48dp touch targets.
final class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  // Phone primaries (in display order): Dashboard, Billing, Inventory,
  // Customers — everything else (Orders, Expenses, Purchases, Suppliers,
  // Reports, Settings) lives behind "More", so the bar never wraps on a phone.
  static const List<int> _phonePrimary = [0, 2, 1, 4];

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    if (!isPhone) {
      return _FullNavigation(
        items: items,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      );
    }
    // Phone: 4 primaries + More
    final primaryIndices = _phonePrimary
        .where((i) => i < items.length)
        .toList();
    final moreIndices = List<int>.generate(
      items.length,
      (i) => i,
    ).where((i) => !primaryIndices.contains(i)).toList();
    final isMoreSelected = moreIndices.contains(selectedIndex);

    final destinations = <NavigationDestination>[
      for (final idx in primaryIndices)
        NavigationDestination(
          icon: Icon(items[idx].icon),
          selectedIcon: Icon(items[idx].selectedIcon),
          label: _phoneLabel(items[idx].label),
        ),
      NavigationDestination(
        icon: const Icon(Icons.more_horiz_outlined),
        selectedIcon: const Icon(Icons.more_horiz),
        label: 'More',
      ),
    ];

    int navSelected = 0;
    for (var i = 0; i < primaryIndices.length; i++) {
      if (primaryIndices[i] == selectedIndex) {
        navSelected = i;
        break;
      }
    }
    if (isMoreSelected) navSelected = destinations.length - 1;

    return _PhoneNavigationBar(
      destinations: destinations,
      selectedIndex: navSelected,
      onDestinationSelected: (navIndex) {
        if (navIndex < primaryIndices.length) {
          onDestinationSelected(primaryIndices[navIndex]);
        } else {
          _showMoreSheet(context, moreIndices, isMoreSelected);
        }
      },
      isMoreSelected: isMoreSelected,
    );
  }

  String _phoneLabel(String label) {
    // Keep labels short so they never wrap at 410dp
    const map = {'Dashboard': 'Home', 'Billing': 'Sales', 'Inventory': 'Stock'};
    return map[label] ?? label;
  }

  void _showMoreSheet(
    BuildContext context,
    List<int> moreIndices,
    bool isMoreSelected,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ...moreIndices.map((idx) {
                final item = items[idx];
                final selected = idx == selectedIndex;
                return ListTile(
                  leading: Icon(
                    selected ? item.selectedIcon : item.icon,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: selected
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppBorderRadius.md,
                  ),
                  selected: selected,
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                  onTap: () {
                    Navigator.of(context).pop();
                    onDestinationSelected(idx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

final class _FullNavigation extends StatelessWidget {
  const _FullNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  int indexOf(AppNavItem item) => items.indexOf(item);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: appColors.divider)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        height: 68,
        elevation: 0,
        backgroundColor: appColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: appColors.softGreen,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppBorderRadius.pill,
        ),
        labelBehavior: items.length > 6
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : appColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(
                item.icon,
                color: indexOf(item) == selectedIndex
                    ? scheme.primary
                    : appColors.textSecondary,
              ),
              selectedIcon: Icon(
                item.selectedIcon,
                color: indexOf(item) == selectedIndex
                    ? scheme.primary
                    : appColors.textSecondary,
              ),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

final class _PhoneNavigationBar extends StatelessWidget {
  const _PhoneNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.isMoreSelected,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isMoreSelected;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.surface,
        border: Border(
          top: BorderSide(color: appColors.divider.withValues(alpha: 0.6)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          height: 56,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor:
              isMoreSelected && selectedIndex == destinations.length - 1
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.primary.withValues(alpha: 0.1),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 0.2,
              height: 1.2,
              color: selected ? scheme.primary : appColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
          destinations: destinations,
        ),
      ),
    );
  }
}

/// Dark green vertical sidebar for tablet/desktop navigation.
final class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.extended = true,
    this.showBrand = true,
    this.shopName,
    this.footer,
  });

  /// Compact rail width (icons only).
  static const double compactWidth = 76;

  /// Extended sidebar width (icons + labels).
  static const double extendedWidth = 240;

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;
  final bool showBrand;

  /// Active business name from Settings; shown under the platform wordmark
  /// when set, so the counter always sees WHICH shop they are operating.
  /// Null/empty keeps the generic edition line. Never hardcoded anywhere.
  final String? shopName;

  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extended ? extendedWidth : compactWidth,
      color: AppColors.primaryDark,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBrand)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  extended ? AppSpacing.lg : AppSpacing.md,
                  AppSpacing.xl,
                  extended ? AppSpacing.lg : AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    BrandMark(
                      variant: BrandMarkVariant.onDark,
                      size: BrandMark.smallSize,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BrewFlow',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (extended) ...[
                            const SizedBox(height: 2),
                            Text(
                              (shopName?.trim().isNotEmpty ?? false)
                                  ? shopName!.trim()
                                  : 'Tea & Jigarthanda Edition',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, thickness: 1, color: Colors.white12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                itemCount: items.length,
                itemBuilder: (context, index) => _SidebarTile(
                  item: items[index],
                  selected: index == selectedIndex,
                  extended: extended,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
            ),
            if (footer != null) ...[
              const Divider(height: 1, thickness: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected ? Colors.white : Colors.white70;
    final content = Row(
      children: [
        Icon(selected ? item.selectedIcon : item.icon, color: foreground),
        if (extended) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorderRadius.md,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: extended ? AppSpacing.lg : AppSpacing.sm,
            vertical: 2,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: extended ? AppSpacing.md : 0,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: AppBorderRadius.md,
            ),
            child: extended
                ? content
                : Tooltip(message: item.label, child: content),
          ),
        ),
      ),
    );
  }
}
