import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:material_ui/material_ui.dart';

/// Loon's material ladder, taken from the shipping app rather than guessed.
///
/// The whole look rests on three numbers: every surface is drawn as its own
/// semantic colour at 42%, never as an opaque block; one 8% step serves as
/// shadow, badge fill and hover wash alike; and the separator colour is
/// multiplied by 0.55 before it is drawn. Depth comes from the single shadow
/// and from the base colours themselves — not from differing alphas, and never
/// from a border.
abstract final class DashboardMaterial {
  /// Cards, panels and status cards: `semantic @ 42%` over the frosted pane.
  static const surfaceAlpha = 0.42;

  /// The one whisper step: shadow, badge background, hover and pressed wash.
  static const whisperAlpha = 0.08;

  /// What a separator's own colour is multiplied by.
  static const separatorAlpha = 0.55;

  /// The card shadow, in CSS terms: `0 5px 16px black @ 8%`.
  static const shadowAlpha = 0.08;
  static const shadowBlur = 16.0;
  static const shadowOffsetY = 5.0;

  /// A badge's height is hard-coded in Loon — it does not follow the font.
  static const badgeHeight = 18.0;

  /// The recessed track of the segmented control. Loon's sits about 27 levels
  /// below the card it is drawn on, which is what reads as a slot cut into the
  /// surface; black at this alpha over the card lands on the same value.
  static const trackAlpha = 0.34;

  /// How much of the selection colour the chosen segment's well carries. Its
  /// label is the accent itself, so the fill only has to warm the slot, not
  /// announce it.
  static const segmentAlpha = 0.20;
}

class DashboardColors {
  const DashboardColors._({
    required this.page,
    required this.card,
    required this.tone,
    required this.tone2,
    required this.track,
    required this.thumb,
    required this.series2,
    required this.direct,
    required this.proxy,
    required this.proxyContainer,
    required this.onProxyContainer,
    required this.ok,
    required this.okContainer,
    required this.onOkContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
    required this.proxyMark,
    required this.rejectMark,
    required this.uploadMark,
    required this.downloadMark,
  });

  factory DashboardColors.of(BuildContext context) {
    final colorScheme = context.colorScheme;
    // The window frosts through vibrancy, so the frosted pane sits behind the
    // whole Flutter view and every translucent fill composites over it. Loon
    // uses one alpha for all of them — 42% — and keeps the three steps apart
    // with their base colours alone; a per-level alpha ladder was what made
    // our cards read as thin haze next to its solid-looking panels. Without
    // the native frost there is nothing to see through, so the same surfaces
    // go opaque.
    final glass = ProviderScope.containerOf(context).read(glassPaneProvider);
    // Over the frost the stack drops one level. The theme's card tone lands
    // *above* the pane once it is blended at 42%, and a card that is lighter
    // than the page stops reading as a panel — measured off Loon, its cards
    // sit a few levels *below* the frosted background and are held apart by
    // their shadow alone. Dropping the three nested levels by one surface is
    // what reproduces that order; the alphas stay at Loon's single 42%.
    final dark = colorScheme.brightness == Brightness.dark;
    Color level(SurfaceLevel surface) => glass && dark
        ? switch (surface) {
            SurfaceLevel.page => colorScheme.surface,
            SurfaceLevel.card => colorScheme.surfaceContainerLowest,
            SurfaceLevel.block => colorScheme.surfaceContainerLow,
            SurfaceLevel.inset => colorScheme.surfaceContainer,
          }
        : surface.colorOf(colorScheme);
    Color surface(Color base) => glass
        ? base.withValues(alpha: DashboardMaterial.surfaceAlpha)
        : base;
    final card = surface(level(SurfaceLevel.card));
    final tone = surface(level(SurfaceLevel.block));
    final tone2 = surface(level(SurfaceLevel.inset));
    final cardBase = level(SurfaceLevel.card);
    return DashboardColors._(
      page: SurfaceLevel.page.colorOf(colorScheme),
      card: card,
      tone: tone,
      tone2: tone2,
      track: colorScheme.surfaceContainerHighest,
      thumb: colorScheme.outline,
      series2: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.45),
        cardBase,
      ),
      ok: colorScheme.success,
      okContainer: colorScheme.successContainer,
      onOkContainer: colorScheme.onSuccessContainer,
      warn: colorScheme.warning,
      warnContainer: colorScheme.warningContainer,
      onWarnContainer: colorScheme.onWarningContainer,
      direct: colorScheme.primary,
      proxy: colorScheme.warning,
      proxyContainer: colorScheme.warningContainer,
      onProxyContainer: colorScheme.onWarningContainer,
      // Loon marks a route with saturated ink, not with a container tone.
      // The theme's warning and error are pastel in dark mode — over the frost
      // they read as peach and pink, while Loon's own marks measure pure
      // orange and a deep red.
      proxyMark: const Color(0xFFFC7E26),
      rejectMark: const Color(0xFFC11C13),
      // The speed chart's two inks. The theme's primary is the same blue for
      // both directions and its 80-tone green goes pastel on a curve, where
      // Loon's pair are a saturated blue and green that hold up as thin lines
      // over the frost.
      uploadMark: const Color(0xFF2F6BFF),
      downloadMark: const Color(0xFF27C93F),
    );
  }

  final Color page;
  final Color card;

  final Color tone;

  final Color tone2;
  final Color track;
  final Color thumb;
  final Color series2;

  /// What a connection sent or fetched straight out of the machine reads in
  /// the app's tint; what went through a proxy reads in the scheme's warm
  /// tone, the one that also fills the mode button that is on.
  final Color direct;
  final Color proxy;
  final Color proxyContainer;
  final Color onProxyContainer;
  final Color ok;
  final Color okContainer;
  final Color onOkContainer;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;

  /// The orange and red Loon paints a route's dot and bar segment with.
  final Color proxyMark;
  final Color rejectMark;

  /// The blue and green the two speed curves are drawn in.
  final Color uploadMark;
  final Color downloadMark;
}

/// Values are the design's CSS shadows. A CSS blur is twice its sigma while
/// Flutter turns a blur radius r into a sigma of 0.577 r + 0.5, so each one
/// goes through [_blur] or it renders a third heavier.
abstract final class DashboardShadows {
  /// The only shadow a card gets, and it gets it in every mode: Loon separates
  /// a card from the frost with `black @ 8%`, radius 16, five points down, and
  /// keeps it whether or not the window is focused. Same in both appearances.
  static List<BoxShadow> card(BuildContext context) => _card;

  static final _card = [
    _shadow(
      (DashboardMaterial.shadowAlpha * 255).round(),
      DashboardMaterial.shadowOffsetY,
      DashboardMaterial.shadowBlur,
    ),
  ];

  static List<BoxShadow> e1(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _e1Dark : _e1Light;

  static List<BoxShadow> e2(BuildContext context) =>
      context.colorScheme.brightness == Brightness.dark ? _e2Dark : _e2Light;

  static BoxShadow _shadow(
    int alpha,
    double y,
    double cssBlur, [
    double spread = 0,
  ]) => BoxShadow(
    color: Color.fromARGB(alpha, 0, 0, 0),
    offset: Offset(0, y),
    blurRadius: _blur(cssBlur),
    spreadRadius: spread,
  );

  static double _blur(double cssBlur) =>
      cssBlur <= 1 ? 0 : (cssBlur / 2 - 0.5) / 0.57735;

  static final _e1Light = [
    _shadow(0x0D, 0.5, 1),
    _shadow(0x0A, 2, 6),
    _shadow(0x17, 12, 32, -6),
  ];

  static final _e1Dark = [_shadow(0x80, 1, 2), _shadow(0x8C, 10, 28, -6)];

  static final _e2Light = [
    _shadow(0x0F, 1, 3),
    _shadow(0x14, 10, 24),
    _shadow(0x38, 32, 64, -12),
  ];

  static final _e2Dark = [_shadow(0x80, 2, 6), _shadow(0xB3, 32, 64, -12)];
}

/// Loon's corner ladder, all of it continuous. A dashboard card is 18 on
/// desktop; on a phone it keeps a slightly larger sweep for the taller tile.
/// The nested steps are the app's own 13 / 12 / 10 / 5, matching Loon's
/// collection items, table headers, tab bar and policy badges.
abstract final class DashboardCorner {
  static const desktopCard = 18.0;
  static const mobileCard = 20.0;
  static const block = 13.0;
  static const mobileBlock = 13.0;
  static const tab = 10.0;
  static const tableHeader = 12.0;
  static const badge = 14.0;
  static const chip = 5.0;
}

final _groupedFormat = NumberFormat.decimalPattern('en');

/// Grouped digits, as the design shows them, until they outgrow a third of a
/// phone's width.
String dashboardCount(int count) =>
    count < 100000 ? _groupedFormat.format(count) : count.compact;

String dashboardTraffic(num bytes) {
  final show = bytes.traffic;
  return '${show.value} ${show.unit}';
}

/// The dashboard's text roles; every figure reads in tabular digits.
abstract final class DashboardText {
  /// Loon's card title measures 26 px of ink at 2.07 px/pt — a 14 pt label,
  /// one step above our own footnote.
  static TextStyle cardTitle(BuildContext context) =>
      AppTextStyle.custom(
        context,
        size: 14,
        leading: 19,
        weight: FontWeight.w600,
      ).copyWith(color: context.colorScheme.onSurfaceVariant);

  /// The big number a summary card leads with. Loon's caps run 45 px at the
  /// same scale, which is a 30 pt face — noticeably smaller than the 40 pt
  /// display step, and what lets the bar and its legend fit under it.
  static TextStyle metric(BuildContext context, {Color? color}) =>
      AppTextStyle.custom(
        context,
        size: 30,
        leading: 34,
        weight: FontWeight.w700,
      ).toTabular.copyWith(color: color, letterSpacing: -0.02 * 30);

  /// The unit trailing a [metric]: 11 pt against the figure's 30, sitting on
  /// the same baseline so the two read as one reading.
  static TextStyle metricUnit(BuildContext context) =>
      AppTextStyle.custom(
        context,
        size: 11,
        leading: 13,
        weight: FontWeight.w500,
      ).copyWith(color: context.colorScheme.onSurfaceVariant);

  /// A legend's label: 10 pt grey. The value below it is 13 pt and starts at
  /// the same left edge, which is what keeps the pair reading as one entry.
  static TextStyle legendLabel(BuildContext context) => AppTextStyle.custom(
    context,
    size: 10,
    leading: 13,
    weight: FontWeight.w500,
  ).copyWith(color: context.colorScheme.onSurfaceVariant);

  /// A speed panel's figure: Loon sets the number at 28 pt and the unit at
  /// 18 pt in the same white, so the two read as one reading. Our 11 pt unit
  /// read as a footnote to it instead.
  static TextStyle speedFigure(BuildContext context) => AppTextStyle.custom(
    context,
    size: 28,
    leading: 32,
    weight: FontWeight.w700,
  ).toTabular.copyWith(letterSpacing: -0.02 * 28);

  static TextStyle speedUnit(BuildContext context) => AppTextStyle.custom(
    context,
    size: 18,
    leading: 22,
    weight: FontWeight.w600,
  ).copyWith(color: context.colorScheme.onSurface);

  /// The direction heading a speed panel: 13 pt, a step above the 10 pt legend
  /// label, because it names a chart rather than annotating a bar.
  static TextStyle speedLabel(BuildContext context) => AppTextStyle.custom(
    context,
    size: 13,
    leading: 17,
    weight: FontWeight.w500,
  ).copyWith(color: context.colorScheme.onSurfaceVariant);

  /// The scale down the chart's side: 11 pt and grey, so the numbers sit
  /// behind the curve instead of competing with the figure above it.
  static TextStyle speedAxis(BuildContext context) => AppTextStyle.custom(
    context,
    size: 11,
    leading: 14,
    weight: FontWeight.w500,
  ).toTabular.copyWith(color: context.colorScheme.onSurfaceVariant);

  static TextStyle legendValue(BuildContext context) => AppTextStyle.custom(
    context,
    size: 13,
    leading: 17,
    weight: FontWeight.w600,
  ).toTabular;

  static TextStyle mobileCardTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true);

  static TextStyle label(BuildContext context, {Color? color}) => AppTextStyle
      .caption1
      .of(context)
      .toTabular
      .copyWith(color: color ?? context.colorScheme.onSurfaceVariant);

  /// Loon's badge label: 10 pt medium, filling the 18 pt badge so the text
  /// sits centered without a second alignment pass.
  static TextStyle badge(
    BuildContext context, {
    Color? color,
    bool large = false,
  }) => AppTextStyle.custom(
    context,
    size: large ? 11 : 10,
    leading: large ? 24 : DashboardMaterial.badgeHeight,
    weight: FontWeight.w500,
  ).toTabular.copyWith(color: color);

  static TextStyle figure(
    BuildContext context,
    AppTextStyle style, {
    Color? color,
  }) => style
      .of(context, emphasized: true)
      .toTabular
      .copyWith(color: color, letterSpacing: -0.02 * style.size);

  static TextStyle unit(
    BuildContext context, [
    AppTextStyle style = AppTextStyle.subheadline,
  ]) => style
      .of(context, emphasized: true)
      .copyWith(color: context.colorScheme.onSurfaceVariant);

  static TextStyle rowTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true);

  /// A process row's app name: 13 pt, the size Loon gives it. The card holds
  /// four rows and three numeric columns besides, so the subheadline step used
  /// elsewhere left names truncated to a few letters.
  static TextStyle processName(BuildContext context) => AppTextStyle.custom(
    context,
    size: 13,
    leading: 17,
    weight: FontWeight.w500,
  );
}
