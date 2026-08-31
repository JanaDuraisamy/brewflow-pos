import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_gradients.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );
  }

  group('theme tokens', () {
    test('approved palette tokens exist', () {
      expect(AppColors.charcoal, const Color(0xFF212121));
      expect(AppColors.gold, const Color(0xFFFFB300));
      expect(AppColors.softGreen, const Color(0xFFE8F5E9));
      expect(AppColors.lightGray, const Color(0xFFF4F6F8));
      expect(AppColors.primary, const Color(0xFF2E7D32));
      expect(AppColors.primaryDark, const Color(0xFF1B5E20));
    });

    test('shadows are subtle and layered', () {
      expect(AppShadows.sm.blurRadius, 6);
      expect(AppShadows.md, hasLength(2));
      expect(AppShadows.lg, hasLength(2));
    });

    test('brand gradient runs from Brew Green to Dark Green', () {
      expect(AppGradients.brand.colors, hasLength(2));
      expect(AppGradients.brand.colors.first, AppColors.primary);
      expect(AppGradients.brand.colors.last, AppColors.primaryDark);
    });

    test('breakpoints map widths to modes', () {
      expect(AppBreakpoints.fromWidth(320), AppBreakpoint.compact);
      expect(AppBreakpoints.fromWidth(700), AppBreakpoint.medium);
      expect(AppBreakpoints.fromWidth(1200), AppBreakpoint.expanded);
    });
  });

  group('BrandMark / BrewFlowBrand', () {
    testWidgets('monogram renders at compact and large sizes', (tester) async {
      await pump(
        tester,
        const Wrap(
          children: [
            BrandMark(size: BrandMark.compactSize),
            BrandMark(size: BrandMark.largeSize),
            BrandMark(variant: BrandMarkVariant.onDark),
          ],
        ),
      );
      expect(find.text('BF'), findsNWidgets(3));
    });

    testWidgets('BrewFlowBrand shows wordmark, edition and tagline', (
      tester,
    ) async {
      await pump(tester, const BrewFlowBrand(showEdition: true));
      expect(find.text('BrewFlow'), findsOneWidget);
      expect(find.text('Tea & Jigarthanda Edition'), findsOneWidget);
      expect(find.text('Smart Business. Simple Billing.'), findsOneWidget);
    });
  });

  group('AppCard / SectionCard', () {
    testWidgets('AppCard renders its child and fires onTap', (tester) async {
      var taps = 0;
      await pump(
        tester,
        AppCard(onTap: () => taps++, child: const Text('card body')),
      );
      expect(find.text('card body'), findsOneWidget);
      await tester.tap(find.text('card body'));
      expect(taps, 1);
    });

    testWidgets('SectionCard renders title, subtitle and trailing', (
      tester,
    ) async {
      await pump(
        tester,
        SectionCard(
          title: 'Sales Overview',
          subtitle: 'Last 7 days',
          trailing: const Icon(Icons.more_horiz),
          child: const Text('chart area'),
        ),
      );
      expect(find.text('Sales Overview'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('chart area'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });
  });

  group('KpiCard / AlertCard', () {
    testWidgets('KpiCard renders label, value and caption', (tester) async {
      await pump(
        tester,
        const KpiCard(
          label: "Today's Sales",
          value: '₹1,23,456.78',
          icon: Icons.payments_outlined,
          caption: '12 bills',
        ),
      );
      expect(find.text("Today's Sales"), findsOneWidget);
      expect(find.text('₹1,23,456.78'), findsOneWidget);
      expect(find.text('12 bills'), findsOneWidget);
    });

    testWidgets('AlertCard shows badge only for a positive count', (
      tester,
    ) async {
      await pump(
        tester,
        Column(
          children: [
            const AlertCard(
              icon: Icons.inventory_2_outlined,
              title: 'Low Stock Alert',
              message: '3 products below threshold',
              count: 3,
            ),
            const AlertCard(
              icon: Icons.event_outlined,
              title: "Today's Reminders",
              message: 'Nothing due',
            ),
          ],
        ),
      );
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text("Today's Reminders"), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('AppAvatar / NotificationBell', () {
    testWidgets('AppAvatar derives the initial from the name', (tester) async {
      await pump(tester, const AppAvatar(name: 'Owner', size: 40));
      expect(find.text('O'), findsOneWidget);
    });

    testWidgets('NotificationBell badge appears only above zero', (
      tester,
    ) async {
      await pump(
        tester,
        Row(
          children: [
            NotificationBell(count: 0),
            NotificationBell(count: 5),
            NotificationBell(count: 120),
          ],
        ),
      );
      expect(find.text('0'), findsNothing);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('SearchField / FilterChip', () {
    testWidgets('SearchField reports typed text and clears', (tester) async {
      final changes = <String>[];
      await pump(
        tester,
        SizedBox(width: 320, child: SearchField(onChanged: changes.add)),
      );
      await tester.enterText(find.byType(TextField), 'BF-000001');
      await tester.pump();
      expect(changes.last, 'BF-000001');
      await tester.tap(find.byTooltip('Clear'));
      expect(changes.last, '');
    });

    testWidgets('AppFilterChip toggles through onSelected', (tester) async {
      var selected = false;
      await pump(
        tester,
        AppFilterChip(
          label: 'Today',
          selected: selected,
          onSelected: (value) => selected = value,
        ),
      );
      await tester.tap(find.text('Today'));
      expect(selected, isTrue);
    });
  });

  group('PrimaryButton / SecondaryButton', () {
    testWidgets('PrimaryButton fires and supports loading', (tester) async {
      var taps = 0;
      await pump(
        tester,
        Column(
          children: [
            PrimaryButton(label: 'Save', onPressed: () => taps++),
            PrimaryButton(label: 'Saving', loading: true),
          ],
        ),
      );
      await tester.tap(find.text('Save'));
      expect(taps, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(
        find.byType(CircularProgressIndicator),
        warnIfMissed: false,
      );
      expect(taps, 1);
    });

    testWidgets('SecondaryButton fires', (tester) async {
      var taps = 0;
      await pump(
        tester,
        SecondaryButton(label: 'Cancel', onPressed: () => taps++),
      );
      await tester.tap(find.text('Cancel'));
      expect(taps, 1);
    });
  });

  group('navigation', () {
    const items = [
      AppNavItem(
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      AppNavItem(
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
      ),
      AppNavItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];

    testWidgets('AppBottomNavigation reports the tapped index', (tester) async {
      var selected = 0;
      await pump(
        tester,
        Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            items: items,
            selectedIndex: selected,
            onDestinationSelected: (index) => selected = index,
          ),
        ),
      );
      await tester.tap(find.text('Orders'));
      expect(selected, 1);
    });

    testWidgets('AppSidebar extended shows labels and reports taps', (
      tester,
    ) async {
      var selected = 0;
      await pump(
        tester,
        AppSidebar(
          items: items,
          selectedIndex: selected,
          extended: true,
          onDestinationSelected: (index) => selected = index,
        ),
      );
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('BrewFlow'), findsOneWidget);
      await tester.tap(find.text('Orders'));
      expect(selected, 1);
    });

    testWidgets('AppSidebar compact hides labels but keeps tap targets', (
      tester,
    ) async {
      var selected = 0;
      await pump(
        tester,
        AppSidebar(
          items: items,
          selectedIndex: selected,
          extended: false,
          showBrand: false,
          onDestinationSelected: (index) => selected = index,
        ),
      );
      expect(find.text('Orders'), findsNothing);
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      expect(selected, 1);
    });
  });

  group('state views', () {
    testWidgets('EmptyState shows icon, title and message', (tester) async {
      await pump(
        tester,
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: 'No orders yet',
          message: 'Sales will appear here.',
        ),
      );
      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Sales will appear here.'), findsOneWidget);
    });

    testWidgets('LoadingState shows a branded spinner', (tester) async {
      await pump(tester, const LoadingState(message: 'Loading…'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets('ErrorState shows the message and retries', (tester) async {
      var retries = 0;
      await pump(
        tester,
        ErrorState(message: 'Could not load data.', onRetry: () => retries++),
      );
      expect(find.text('Could not load data.'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      expect(retries, 1);
    });
  });

  group('ResponsiveBuilder', () {
    testWidgets('reports the breakpoint for the available width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      AppBreakpoint? seen;

      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: ResponsiveBuilder(
            builder: (context, breakpoint) {
              seen = breakpoint;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, AppBreakpoint.compact);

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(seen, AppBreakpoint.expanded);
    });
  });
}
