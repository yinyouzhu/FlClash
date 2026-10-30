import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  test('the window picks the density', () {
    DashboardDensity of(double width, double height) =>
        DashboardDensity.of(Size(width, height));

    expect(of(1220, 900), DashboardDensity.standard);
    expect(of(1220, 824), DashboardDensity.standard);
    expect(of(1220, 823), DashboardDensity.compact);
    expect(of(1220, 500), DashboardDensity.compact);
    expect(of(1039, 900), DashboardDensity.compact);
    expect(of(740, 900), DashboardDensity.compact);
    expect(of(739, 900), DashboardDensity.standard);
    expect(of(640, 900), DashboardDensity.standard);
    expect(of(640, 823), DashboardDensity.compact);
    expect(of(639, 900), DashboardDensity.mobile);
    expect(dashboardColumnsOf(740), 4);
    expect(dashboardColumnsOf(739), 2);
  });

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Future<void> pumpDashboard(
    WidgetTester tester,
    Size size, {
    SupportPlatform platform = SupportPlatform.MacOS,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: DashboardView(platform: platform)),
      ),
    );
    await tester.pump();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  }

  Rect rectOf(WidgetTester tester, Type type) =>
      tester.getRect(find.byType(type).first);

  double scrollExtentOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .maxScrollExtent;

  double gapOf(WidgetTester tester) => cardSpacingOf(
    tester.element(find.byType(NodeHealthCard)),
    container.read(viewModeProvider),
  );

  testWidgets('the wide window fills four rows with the home cards', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1220, 824));
    final gap = gapOf(tester);

    final bar = tester.getRect(find.byType(HomeHeader));
    final health = rectOf(tester, NodeHealthCard);
    final split = rectOf(tester, ConnectionSplitCard);
    final summary = rectOf(tester, TrafficSummaryCard);
    final speed = rectOf(tester, SpeedOverviewCard);
    final service = rectOf(tester, ServiceStatusCard);
    final processes = rectOf(tester, ProcessListCard);
    final profile = rectOf(tester, ProfilesCard);

    // The header is the page's bar, over the grid rather than in it.
    expect(bar.bottom, lessThan(health.top));
    expect(health.height, closeTo(188, 0.01));
    expect(split.top, closeTo(health.top, 0.01));
    expect(summary.top, closeTo(health.top, 0.01));
    expect(split.width, closeTo(health.width, 0.01));
    expect(summary.width, closeTo(health.width, 0.01));
    expect(split.left, closeTo(health.right + gap, 0.01));
    expect(summary.left, closeTo(split.right + gap, 0.01));

    expect(speed.top, closeTo(health.bottom + gap, 0.01));
    expect(speed.height, closeTo(288, 0.01));
    expect(service.top, closeTo(speed.top, 0.01));
    expect(speed.width, closeTo(service.width * 2, 0.01));
    expect(service.left, closeTo(speed.right + gap, 0.01));

    expect(processes.top, closeTo(speed.bottom + gap, 0.01));
    expect(processes.height, closeTo(312, 0.01));
    expect(profile.top, closeTo(processes.top, 0.01));
    expect(processes.width, closeTo(profile.width * 2, 0.01));
    expect(profile.left, closeTo(processes.right + gap, 0.01));
    expect(profile.right, closeTo(summary.right, 0.01));

    expect(find.byType(CurrentOutboundCard), findsNothing);
    expect(find.byType(OutboundModeBar), findsNothing);
    expect(find.byType(MemoryInfo), findsNothing);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('every home row shares one left and one right edge', (
    tester,
  ) async {
    for (final size in const [Size(1220, 824), Size(1000, 900)]) {
      await pumpDashboard(tester, size);

      final left = rectOf(tester, NodeHealthCard).left;
      for (final type in const [
        NodeHealthCard,
        SpeedOverviewCard,
        ProcessListCard,
      ]) {
        expect(rectOf(tester, type).left, closeTo(left, 0.01));
      }
      expect(
        rectOf(tester, TrafficSummaryCard).right,
        closeTo(rectOf(tester, ProfilesCard).right, 0.01),
      );
      expect(tester.takeException(), isNull);

      await teardown(tester);
    }
  });

  testWidgets('a wide window keeps the row heights the design sets', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1440, 900));

    expect(rectOf(tester, NodeHealthCard).height, closeTo(188, 0.01));
    expect(rectOf(tester, SpeedOverviewCard).height, closeTo(288, 0.01));
    expect(rectOf(tester, ProcessListCard).height, closeTo(312, 0.01));
    expect(find.byType(ServiceStatusCard), findsOneWidget);
    expect(find.byType(MemoryInfo), findsNothing);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('the default window opens on the home grid beside the expanded '
      'sidebar and a title bar', (tester) async {
    const sidebar = 158.0;
    const titleBar = 32.0;
    await pumpDashboard(
      tester,
      Size(
        defaultWindowSize.width - sidebar,
        defaultWindowSize.height - titleBar,
      ),
    );

    expect(find.byType(HomeHeader), findsOneWidget);
    expect(find.byType(ProcessListCard), findsOneWidget);
    expect(find.byType(ProfilesCard), findsOneWidget);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a short window keeps the compact row heights and scrolls', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1220, 600));

    expect(rectOf(tester, NodeHealthCard).height, closeTo(168, 0.01));
    expect(rectOf(tester, SpeedOverviewCard).height, closeTo(210, 0.01));
    expect(rectOf(tester, ProcessListCard).height, closeTo(194, 0.01));
    expect(scrollExtentOf(tester), greaterThan(0));
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a short window scrolls the page as one list', (tester) async {
    for (final size in const [Size(1000, 660), Size(1000, 560)]) {
      await pumpDashboard(tester, size);

      expect(scrollExtentOf(tester), greaterThan(0));
      expect(find.byType(Scrollable), findsOneWidget);
      expect(find.byType(ConnectionStatsCard), findsNothing);
      expect(find.byType(ConnectionsTableCard), findsNothing);
      expect(tester.takeException(), isNull);

      await teardown(tester);
    }
  });

  testWidgets('the home grid starts at four columns and the stacked cards '
      'below it', (tester) async {
    await pumpDashboard(tester, const Size(924, 737));

    expect(find.byType(HomeHeader), findsOneWidget);
    expect(find.byType(ProcessListCard), findsOneWidget);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(tester.takeException(), isNull);

    await teardown(tester);

    await pumpDashboard(tester, const Size(739, 737));

    expect(find.byType(HomeHeader), findsNothing);
    expect(find.byType(CurrentOutboundCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a wide window centres a grid that stops growing', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(2560, 1440));

    // The home grid caps its width at 1440 and centres what is left over.
    final health = rectOf(tester, NodeHealthCard);
    final profile = rectOf(tester, ProfilesCard);
    expect(profile.right - health.left, closeTo(1440, 0.01));
    expect(health.left - 16, closeTo(2560 - 24 - profile.right, 0.01));
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('a resize lays the cards out for the new width in its first '
      'frame, before the view size catches up', (tester) async {
    await pumpDashboard(tester, const Size(1440, 900));
    expect(find.byType(HomeHeader), findsOneWidget);

    Future<void> resize(Size size) async {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Future<void> settle(Size size) async {
      container.read(viewSizeProvider.notifier).value = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await resize(const Size(600, 800));
    // The grid reads its own constraints, so it is already on the stacked
    // cards; the bar reads the view size, which learns the resize a frame on.
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(find.byType(HomeHeader), findsOneWidget);

    await settle(const Size(600, 800));
    expect(find.byType(HomeHeader), findsNothing);

    await resize(const Size(720, 900));
    expect(rectOf(tester, OutboundModeBar).width, closeTo(720 - 16 - 24, 0.01));

    await resize(const Size(1440, 900));
    await settle(const Size(1440, 900));
    expect(find.byType(HomeHeader), findsOneWidget);
    expect(find.byType(ConnectionsTableCard), findsNothing);

    await teardown(tester);
  });

  testWidgets('larger text grows the box of every line', (tester) async {
    container.listen(localIpProvider, (_, _) {});
    container.read(localIpProvider.notifier).value = '192.168.100.200';
    List<String> clipped() => [
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      ))
        if (paragraph.getMaxIntrinsicHeight(paragraph.size.width) >
            paragraph.size.height + 0.5)
          paragraph.text.toPlainText(),
    ];
    for (final (size, platform) in const [
      (Size(1440, 900), SupportPlatform.MacOS),
      (Size(1000, 1000), SupportPlatform.MacOS),
      (Size(412, 915), SupportPlatform.Android),
    ]) {
      for (final textScale in const [1.2, 1.4]) {
        await pumpDashboard(
          tester,
          size,
          platform: platform,
          textScale: textScale,
        );
        expect(clipped(), isEmpty, reason: '$size x$textScale');
        expect(tester.takeException(), isNull);
      }
    }

    await teardown(tester);
  });

  testWidgets('a mid-width window stacks the same cards in two columns', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(720, 900));
    final gap = cardSpacingOf(
      tester.element(find.byType(CurrentOutboundCard)),
      ViewMode.laptop,
    );

    final current = rectOf(tester, CurrentOutboundCard);
    final upload = rectOf(tester, SpeedCard);
    final mode = rectOf(tester, OutboundModeBar);
    final tun = tester.getRect(find.byType(NetworkTakeoverTile).last);
    final intranet = rectOf(tester, IntranetIpCard);
    final profile = rectOf(tester, ProfilesCard);

    expect(current.width, 720 - 16 - 24);
    expect(current.width, closeTo(upload.width * 2 + gap, 0.01));
    expect(mode.width, current.width);
    expect(tun.width, closeTo(upload.width, 0.01));
    expect(intranet.top, tun.bottom + gap);
    expect(profile.top, intranet.top);
    expect(profile.left, closeTo(intranet.right + gap, 0.01));
    final service = rectOf(tester, ServiceStatusCard);
    expect(service.width, closeTo(upload.width, 0.01));
    expect(rectOf(tester, MemoryInfo).top, service.top);
    expect(find.byType(OutboundModeCard), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byType(ProxyGroupsSummaryCard),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final stats = rectOf(tester, ConnectionStatsCard);
    final groups = rectOf(tester, ProxyGroupsSummaryCard);
    expect(stats.width, closeTo(upload.width, 0.01));
    expect(groups.top, stats.top);
    expect(groups.left, closeTo(stats.right + gap, 0.01));
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardown(tester);
  });

  testWidgets('larger text grows the rows and narrows the grid', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1400, 1000), textScale: 1.2);
    expect(rectOf(tester, NodeHealthCard).height, closeTo(188 * 1.2, 0.01));
    expect(tester.takeException(), isNull);

    await pumpDashboard(tester, const Size(880, 1000), textScale: 1.2);
    final current = rectOf(tester, CurrentOutboundCard);
    expect(current.width, 880 - 16 - 24);
    expect(current.height, closeTo(208 * 1.2, 0.01));
    expect(tester.takeException(), isNull);

    await pumpDashboard(tester, const Size(760, 1000), textScale: 1.2);
    expect(find.byType(ConnectionsTableCard), findsNothing);
    expect(find.byType(OutboundModeBar), findsNothing);
    expect(rectOf(tester, CurrentOutboundCard).width, 560);

    await teardown(tester);
  });

  testWidgets('a narrow desktop window shows the phone cards in a centred '
      'column, takeover in place of the VPN', (tester) async {
    await pumpDashboard(tester, const Size(620, 700));

    final card = rectOf(tester, CurrentOutboundCard);
    expect(card.width, 560);
    expect(card.center.dx, closeTo(310, 0.01));
    expect(find.byType(NetworkTakeoverCard), findsOneWidget);
    expect(find.byType(VpnCard), findsNothing);
    expect(find.byType(OutboundModeCard), findsOneWidget);
    expect(find.byType(OutboundModeBar), findsNothing);

    await teardown(tester);
  });

  testWidgets('a phone shows the saved cards edge to edge', (tester) async {
    await pumpDashboard(
      tester,
      const Size(400, 900),
      platform: SupportPlatform.Android,
    );

    final card = rectOf(tester, CurrentOutboundCard);
    expect(card.left, 16);
    expect(card.right, 400 - 16);
    expect(find.byType(VpnCard), findsOneWidget);
    expect(find.byType(NetworkTakeoverCard), findsNothing);

    await teardown(tester);
  });

  testWidgets('a tablet or a landscape phone gets the same home grid', (
    tester,
  ) async {
    for (final size in const [Size(1280, 800), Size(915, 412)]) {
      await pumpDashboard(tester, size, platform: SupportPlatform.Android);

      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(ServiceStatusCard), findsOneWidget);
      expect(find.byType(DashboardSwitchRow), findsNothing);
      expect(find.byType(VpnTile), findsNothing);
      expect(find.byType(NetworkTakeoverTile), findsNothing);
      expect(tester.takeException(), isNull);

      await teardown(tester);
    }
  });
}
