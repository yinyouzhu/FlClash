import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit.dart';
import 'layout.dart';
import 'style.dart';
import 'widget_registry.dart';
import 'widgets/core_status_button.dart';
import 'widgets/widgets.dart';

// Narrower columns leave a pair of service cells too tight for a status, so
// the grid stacks them in one.
class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.platform});

  /// The host's platform when null.
  final SupportPlatform? platform;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  var _editing = false;
  final _cardKeys = <DashboardWidget, GlobalKey>{};

  void _setEditing(bool editing) {
    setState(() => _editing = editing);
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final viewSize = ref.watch(viewSizeProvider);
    final sideWidth = ref.watch(sideWidthProvider);
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final size = Size(viewSize.width - sideWidth, viewSize.height) / scale;
    final layout = DashboardDensity.of(size);
    final editable = !layout.isDesktop;
    if (!editable) {
      _editing = false;
    }
    final editing = _editing;
    // The home grid carries its own bar: the title, the profile in use and
    // the mode on one row, so the page needs no title of its own.
    final homeBar =
        !editing && layout.isDesktop && dashboardColumnsOf(size.width) >= 4;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: homeBar
          ? null
          : editing
          ? appLocalizations.editDashboard
          : appLocalizations.dashboard,
      titleWidget: homeBar ? const HomeHeader() : null,
      barHeight: homeBar ? HomeHeader.barHeight : null,
      actions: [if (!editing && coreLib == null) const CoreStatusButton()],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false),
            )
          : null,
      iconActions: [
        if (editable && !editing)
          IconButtonData(
            glyph: AppGlyphs.edit,
            tooltip: appLocalizations.editDashboard,
            onPressed: () => _setEditing(true),
          ),
      ],
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          final layout = DashboardDensity.of(room);
          return DashboardDensityScope(
            density: layout,
            scale: scale,
            child: layout.isDesktop
                ? _DesktopDashboard(
                    platform: platform,
                    columns: dashboardColumnsOf(room.width),
                    gap: gap,
                  )
                : _MobileDashboard(
                    platform: platform,
                    gap: gap,
                    editing: editing,
                    cardKeyOf: _cardKeyOf,
                    onDone: () => _setEditing(false),
                  ),
          );
        },
      ),
    );
  }
}

/// A wide desktop window gets the home grid; a narrow one keeps the stacked
/// cards so nothing is squeezed under four columns.
class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.platform,
    required this.columns,
    required this.gap,
  });

  final SupportPlatform platform;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (columns >= 4) {
      return _HomeDashboard(gap: gap);
    }
    final compact = DashboardDensityScope.of(context).isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      context.contentTopPadding,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    );
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    final middleHeight = (compact ? 152 : 176) * scale;
    final summaryHeight = (compact ? 112 : 120) * scale;
    final switches =
        DashboardWidget.networkTakeover.platforms.contains(platform)
        ? const [
            Expanded(child: NetworkTakeoverTile(TakeoverSwitch.systemProxy)),
            Expanded(child: NetworkTakeoverTile(TakeoverSwitch.tun)),
          ]
        : const [Expanded(child: VpnTile())];
    Widget pair(Widget start, Widget end) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        Expanded(child: RepaintBoundary(child: start)),
        Expanded(child: RepaintBoundary(child: end)),
      ],
    );
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: base,
      child: Column(
        spacing: gap,
        children: [
          SizedBox(
            height: topHeight,
            child: const RepaintBoundary(child: CurrentOutboundCard()),
          ),
          SizedBox(
            height: topHeight,
            child: pair(
              const SpeedCard(direction: TrafficDirection.upload),
              const SpeedCard(direction: TrafficDirection.download),
            ),
          ),
          SizedBox(
            height: controlHeight,
            child: const RepaintBoundary(child: OutboundModeBar()),
          ),
          SizedBox(
            height: controlHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: gap,
              children: switches,
            ),
          ),
          SizedBox(
            height: middleHeight,
            child: pair(const IntranetIpCard(), const ProfilesCard()),
          ),
          SizedBox(
            height: middleHeight,
            child: pair(const ServiceStatusCard(), const MemoryInfo()),
          ),
          SizedBox(
            height: summaryHeight,
            child: pair(
              const ConnectionStatsCard(),
              const ProxyGroupsSummaryCard(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The home grid of a wide window: a status row, the live speed across the
/// full width, and the busiest processes beside the service probes.
class _HomeDashboard extends ConsumerStatefulWidget {
  const _HomeDashboard({required this.gap});

  final double gap;

  @override
  ConsumerState<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends ConsumerState<_HomeDashboard>
    with
        WidgetsBindingObserver,
        ActivePollingMixin<_HomeDashboard>,
        RouteMotionHoldMixin<_HomeDashboard>,
        ConnectionsPolling<_HomeDashboard> {
  static const _maxWidth = 1440.0;

  /// The three rows measured off Loon's window at 994x688, as one sum: the
  /// grid is fitted to the height the viewport actually has.
  static const _baseRows = 147.0 + 215.0 + 218.0;

  /// Below this the cards' own contents start to clip, so the page stops
  /// squeezing them and scrolls instead.
  static const _minRowFit = 0.8;

  @override
  bool get pollsConnections => true;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    // Counted as the Core opens each connection, not from the list of the ones
    // still open: that list empties as connections finish, and a number that
    // falls back while nothing is wrong reads as a bug.
    final session = ref.watch(sessionConnectionsProvider);
    // The totals the Core keeps, rather than a running sum of the connections
    // this page happened to see: a connection that opens and closes inside one
    // beat never shows up in a poll, and on a page of short requests that is
    // most of the traffic.
    final totals = ref.watch(trafficTotalsProvider);
    final all = (totals.all.up + totals.all.down).toInt();
    final proxy = (totals.proxy.up + totals.proxy.down).toInt();
    final direct = math.max(0, all - proxy);
    // Measured off Loon's own window at 994x688: 15 clear on the left, 16 on
    // the right, a 12 gutter, and three rows of 147 / 215 / 218 that stay put
    // however large the window is. Matching those numbers instead of keeping
    // our own proportions is what makes the two panes line up card for card.
    final padding = EdgeInsetsDirectional.fromSTEB(
      15,
      context.contentTopPadding - 8,
      16,
      22 + MediaQuery.paddingOf(context).bottom,
    );
    // Loon does not use one gutter in both directions: cards sit 12 apart
    // across and 15.5 apart down, and the extra air between rows is a large
    // part of why its grid reads calm. Measured off its window at 994x688.
    const gap = 12.0;
    const rowGap = 15.5;
    Widget row(List<(int, Widget)> cards) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        for (final (flex, card) in cards)
          Expanded(
            flex: flex,
            child: RepaintBoundary(child: card),
          ),
      ],
    );
    // The rows are a ratio to fit the window to, not a fixed size to trust.
    // At 994x688 they land on Loon's 147 / 215 / 218; at any other height they
    // give back or take up the slack, which is what keeps the page off the
    // scroller instead of overflowing it by the couple of points that a
    // bottom inset is worth.
    Widget gridOf(double fit) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Column(
          spacing: rowGap,
          children: [
            SizedBox(
              height: 147 * scale * fit,
              child: row([
                (1, const NodeHealthCard()),
                (
                  1,
                  ConnectionSplitCard(
                    direct: session.direct,
                    proxy: session.proxy,
                    reject: session.reject,
                  ),
                ),
                (1, TrafficSummaryCard(direct: direct, proxy: proxy)),
              ]),
            ),
            SizedBox(
              height: 215 * scale * fit,
              child: row([(1, const SpeedOverviewCard())]),
            ),
            SizedBox(
              height: 218 * scale * fit,
              child: row([
                (1, ProcessListCard(processes: _processesOf(connections))),
                // Where the profiles card used to sit, at its size: the two
                // panels are read together while traffic is running, and the
                // speed graph wants the whole row above them.
                (1, const ServiceStatusCard()),
              ]),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight - padding.vertical - rowGap * 2;
        final fit = room / (_baseRows * scale);
        // Past Loon's own proportions there is nothing to gain by stretching
        // further, so a taller window keeps the grid at its measured size.
        final fitted = fit.clamp(_minRowFit, 1.0).toDouble();
        // The home grid does not scroll: a drag that starts on a card belongs
        // to the card, not to the page. Only a window too short to hold the
        // cards at their minimum hands the page back to the scroller — the
        // window can be dragged down to 380x400, where they would not fit.
        return SingleChildScrollView(
          physics: fit < _minRowFit
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: padding,
          child: gridOf(fitted),
        );
      },
    );
  }
}

List<ProcessUsage> _processesOf(List<TrackerInfo> connections) {
  final totals = <String, ({int traffic, int connections, int speed})>{};
  for (final item in connections) {
    final process = item.metadata.process.trim();
    if (process.isEmpty) continue;
    final current = totals[process];
    totals[process] = (
      traffic: (current?.traffic ?? 0) + item.upload + item.download,
      connections: (current?.connections ?? 0) + 1,
      speed:
          (current?.speed ?? 0) +
          (item.uploadSpeed ?? 0) +
          (item.downloadSpeed ?? 0),
    );
  }
  return [
    for (final entry in totals.entries)
      ProcessUsage(
        name: entry.key,
        traffic: entry.value.traffic,
        connections: entry.value.connections,
        speed: entry.value.speed,
      ),
  ]..sort((a, b) => b.traffic.compareTo(a.traffic));
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.platform,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    final top = context.contentTopPadding;
    final bottom = 16 + context.bottomInset;
    return CustomScrollView(
      // A viewport per card lays them all out and holds the scroll end still.
      scrollCacheExtent: editing
          ? ScrollCacheExtent.viewport(DashboardWidget.values.length.toDouble())
          : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = dashboardMobileSideOf(constraints.crossAxisExtent);
            final widgets = [
              for (final widget in saved)
                if (widget.platforms.contains(platform)) widget,
            ];
            if (editing) {
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              // A lazy list estimates the cards it has not laid out from the
              // ones it has; cards this uneven move the scroll end as it goes.
              sliver: SliverToBoxAdapter(
                child: Column(
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      RepaintBoundary(
                        key: cardKeyOf(widget),
                        child: widget.card,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
