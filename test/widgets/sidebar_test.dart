import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/sidebar.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

final _paneFinder = find
    .byWidgetPredicate((widget) => widget is Material && widget.elevation > 0)
    .first;

const _destinations = [
  SidebarDestination(glyph: AppGlyphs.dashboard, label: 'Dashboard'),
  SidebarDestination(glyph: AppGlyphs.proxies, label: 'Proxies'),
  SidebarDestination(glyph: AppGlyphs.profiles, label: 'Profiles'),
];

Finder _glyph(Glyph glyph) => find.byWidgetPredicate(
  (widget) => widget is AnimatedGlyph && widget.glyph == glyph,
);

double _fillOf(WidgetTester tester, Glyph glyph) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: _glyph(glyph), matching: find.byType(CustomPaint)),
  );
  return (paint.painter! as GlyphPainter).fill;
}

Widget _sidebar({
  List<SidebarDestination> destinations = _destinations,
  int selectedIndex = 0,
  bool expanded = true,
  ValueChanged<int>? onSelected,
  VoidCallback? onToggle,
  Size windowControls = Size.zero,
  EdgeInsets safePadding = EdgeInsets.zero,
  String? version,
}) {
  return TestApp(
    wrapInProviderScope: true,
    child: Scaffold(
      body: Row(
        children: [
          SizedBox(
            height: 400,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(padding: safePadding),
                child: NavigationSidebar(
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  expanded: expanded,
                  onSelected: onSelected ?? (_) {},
                  onToggle: onToggle,
                  windowControls: windowControls,
                  title: 'FlClash',
                  statusLabel: 'Disconnected',
                  version: version,
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox.expand(key: ValueKey('content'))),
        ],
      ),
    ),
  );
}

Finder get _sidebarFinder => find.byType(NavigationSidebar);

Finder _labels(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate(
    (widget) => widget is Opacity && widget.alwaysIncludeSemantics,
  ),
);

Iterable<double> _labelOpacities(WidgetTester tester, String label) {
  return tester.widgetList<Opacity>(_labels(label)).map((o) => o.opacity);
}

Finder _shown(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is Opacity &&
        widget.alwaysIncludeSemantics &&
        widget.opacity == 1,
  ),
  matching: find.text(label),
);

Finder _rowTooltip(String message) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == message,
);

void main() {
  testWidgets('the selected row carries an accent fill and label', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebar(selectedIndex: 1));

    final primary = Theme.of(
      tester.element(_sidebarFinder),
    ).colorScheme.primary;
    final row = tester.widget<Material>(
      find
          .ancestor(
            of: _glyph(AppGlyphs.proxies),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(row.color, primary.withValues(alpha: 0.12));
    expect(tester.widget<Text>(find.text('Proxies')).style?.color, primary);
    expect(tester.getSize(_sidebarFinder).width, 158);
    expect(_labelOpacities(tester, 'Proxies'), [1]);
    expect(
      tester.getSemantics(find.text('Proxies')),
      isSemantics(isSelected: true, isButton: true),
    );
  });

  testWidgets('the brand block pairs the mark with the app name and version', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebar(version: 'v1.2.3'));

    expect(find.text('FlClash'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('v1.2.3'), findsOneWidget);

    final logo = tester.getRect(
      find.descendant(of: _sidebarFinder, matching: find.byType(Image)),
    );
    expect(logo.size, const Size(28, 28));
    expect(logo.left, 18);

    await tester.pumpWidget(_sidebar(expanded: false, version: 'v1.2.3'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(Image)).dx, 24);
    expect(_labelOpacities(tester, 'FlClash'), [0]);
  });

  testWidgets('only the selected row fills its icon', (tester) async {
    await tester.pumpWidget(_sidebar());
    expect(_fillOf(tester, AppGlyphs.dashboard), 1);
    expect(_fillOf(tester, AppGlyphs.profiles), 0);

    await tester.pumpWidget(_sidebar(selectedIndex: 2));
    await tester.pumpAndSettle();
    expect(_fillOf(tester, AppGlyphs.dashboard), 0);
    expect(_fillOf(tester, AppGlyphs.profiles), 1);
  });

  testWidgets('the toggle widens the sidebar in place when it can', (
    tester,
  ) async {
    var toggled = 0;
    int? selected;
    await tester.pumpWidget(
      _sidebar(
        expanded: false,
        onToggle: () => toggled++,
        onSelected: (index) => selected = index,
      ),
    );

    expect(tester.getSize(_sidebarFinder).width, 48);
    expect(_labelOpacities(tester, 'Proxies'), [0]);
    expect(_rowTooltip('Proxies'), findsOneWidget);
    await tester.tap(_glyph(AppGlyphs.profiles));
    expect(selected, 2);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(toggled, 1);
    expect(find.text('Proxies'), findsOneWidget);

    await tester.pumpWidget(_sidebar(onToggle: () {}));
    await tester.pump(const Duration(milliseconds: 120));
    final width = tester.getSize(_sidebarFinder).width;
    expect(width, allOf(greaterThan(48), lessThan(158)));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.getSize(_sidebarFinder).width, 158);
    expect(find.byTooltip('Collapse'), findsOneWidget);
  });

  testWidgets('an expanded row whose label is cut off keeps its tooltip', (
    tester,
  ) async {
    const long = 'Подключения и активные соединения';
    await tester.pumpWidget(
      _sidebar(
        destinations: const [
          ..._destinations,
          SidebarDestination(glyph: AppGlyphs.dns, label: 'DNS'),
          SidebarDestination(glyph: AppGlyphs.connections, label: long),
        ],
        onToggle: () {},
      ),
    );

    expect(_rowTooltip(long), findsOneWidget);
    expect(_rowTooltip('DNS'), findsNothing);
  });

  testWidgets('the toggle glyph follows the pane as it widens', (tester) async {
    List<Rect> glyph(String tooltip) => [
      for (final shape
          in tester
              .widget<GlyphIcon>(
                find.descendant(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(GlyphIcon),
                ),
              )
              .glyph
              .shapes)
        shape.path.getBounds(),
    ];

    await tester.pumpWidget(_sidebar(expanded: false, onToggle: () {}));
    final collapsed = glyph('Expand');

    await tester.pumpWidget(_sidebar(onToggle: () {}));
    await tester.pump(const Duration(milliseconds: 120));
    final midway = glyph('Collapse');
    expect(midway, isNot(collapsed));

    await tester.pumpAndSettle();
    expect(glyph('Collapse'), isNot(midway));
  });

  testWidgets('window controls keep their corner clear', (tester) async {
    await tester.pumpWidget(
      _sidebar(
        expanded: false,
        onToggle: () {},
        windowControls: const Size(78, 32),
      ),
    );

    final sidebar = tester.getRect(_sidebarFinder);
    expect(sidebar.width, 78);
    final logo = tester.getRect(
      find.descendant(of: _sidebarFinder, matching: find.byType(Image)),
    );
    expect(logo.top, greaterThanOrEqualTo(sidebar.top + 32));
    expect(logo.center.dx, sidebar.center.dx);
    expect(tester.getCenter(find.byTooltip('Expand')).dx, sidebar.center.dx);
    expect(tester.getCenter(_glyph(AppGlyphs.profiles)).dx, sidebar.center.dx);
    final selectedItem = tester.getRect(
      find
          .ancestor(
            of: _glyph(AppGlyphs.dashboard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(selectedItem.size, const Size(54, 40));
    expect(selectedItem.center.dx, sidebar.center.dx);

    final folder = tester.getCenter(_glyph(AppGlyphs.profiles));
    await tester.pumpWidget(
      _sidebar(onToggle: () {}, windowControls: const Size(78, 32)),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(_sidebarFinder).width, 158);
    expect(tester.getCenter(_glyph(AppGlyphs.profiles)), folder);
  });

  group('without room to widen', () {
    Future<void> openOverlay(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Expand'));
      await tester.pumpAndSettle();
      expect(find.text('Proxies'), findsNWidgets(2));
    }

    testWidgets('the toggle opens the pane over the content', (tester) async {
      await tester.pumpWidget(_sidebar(expanded: false));
      final contentWidth = tester
          .getSize(find.byKey(const ValueKey('content')))
          .width;

      await openOverlay(tester);

      expect(tester.getSize(_sidebarFinder).width, 48);
      expect(
        tester.getSize(find.byKey(const ValueKey('content'))).width,
        contentWidth,
      );
      expect(_labelOpacities(tester, 'Proxies'), unorderedEquals([0, 1]));
      // The pane widens in place, so the toggle keeps its row and only slides
      // with the row inset.
      expect(
        tester.getCenter(find.byTooltip('Collapse')).dy,
        tester.getCenter(find.byTooltip('Expand')).dy,
      );
      final colorScheme = Theme.of(tester.element(_sidebarFinder)).colorScheme;
      final pane = tester.widget<Material>(_paneFinder);
      expect(pane.color, colorScheme.chromeSurface);
      expect(
        (pane.shape! as BorderDirectional).end,
        Divider.createBorderSide(tester.element(_sidebarFinder)),
      );

      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(find.text('Proxies'), findsOneWidget);
    });

    testWidgets('the pane covers the safe area around the sidebar', (
      tester,
    ) async {
      const safePadding = EdgeInsets.only(left: 40, top: 24, bottom: 16);
      await tester.pumpWidget(
        _sidebar(expanded: false, safePadding: safePadding),
      );
      final sidebar = tester.getRect(_sidebarFinder);
      expect(sidebar.width, 48 + safePadding.left);
      final toggle = tester.getTopLeft(find.byTooltip('Expand'));
      expect(toggle.dx, greaterThanOrEqualTo(sidebar.left + safePadding.left));
      expect(toggle.dy, greaterThanOrEqualTo(sidebar.top + safePadding.top));

      await openOverlay(tester);

      final pane = tester.getRect(_paneFinder);
      expect(pane.topLeft, sidebar.topLeft);
      expect(pane.height, sidebar.height);
      expect(pane.width, 158 + safePadding.left);
      expect(tester.getTopLeft(find.byTooltip('Collapse')).dy, toggle.dy);
    });

    testWidgets('choosing a row selects it and closes the pane', (
      tester,
    ) async {
      int? selected;
      await tester.pumpWidget(
        _sidebar(expanded: false, onSelected: (index) => selected = index),
      );
      await openOverlay(tester);

      await tester.tap(_shown('Profiles'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.text('Profiles'), findsOneWidget);
    });

    testWidgets('a tap outside or escape dismisses the pane', (tester) async {
      await tester.pumpWidget(_sidebar(expanded: false));

      await openOverlay(tester);
      await tester.tapAt(const Offset(600, 300));
      await tester.pumpAndSettle();
      expect(find.text('Proxies'), findsOneWidget);

      await openOverlay(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Proxies'), findsOneWidget);
    });

    testWidgets('a tooltip inside the pane lays out over it', (tester) async {
      await tester.pumpWidget(_sidebar(expanded: false));
      await openOverlay(tester);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(
        location: tester.getCenter(find.byTooltip('Collapse')),
      );
      await tester.pump(const Duration(seconds: 1));
      // The row now carries the label itself, and the tooltip floats over the
      // pane on top of it, so both copies are on screen.
      expect(find.text('Collapse'), findsNWidgets(2));
    });

    testWidgets('widening the window closes the pane', (tester) async {
      await tester.pumpWidget(_sidebar(expanded: false));
      await openOverlay(tester);

      await tester.pumpWidget(_sidebar(expanded: false, onToggle: () {}));
      await tester.pump();
      expect(find.text('Proxies'), findsOneWidget);
    });
  });
}
