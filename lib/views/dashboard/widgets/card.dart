import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';

EdgeInsets dashboardCardPadding(DashboardDensity density) => switch (density) {
  // Loon's cards read airy: the content clears the side edges by more than a
  // row gap. Only the horizontal step is raised — the vertical budget of the
  // tightest card (流量统计) is already spent, and 24 there overflows it.
  DashboardDensity.standard => const EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 20,
  ),
  // Loon measures 19 clear on the left and 18.5 on top of its own cards, so
  // the compact pane — the size its window actually runs at — uses the same.
  DashboardDensity.compact => const EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 18,
  ),
  DashboardDensity.mobile => const EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 18,
  ),
};

/// Padding for the two summary cards, which Loon lays out on a fixed rhythm
/// rather than centring: 20 pt above the title, 10 pt below the legend, so the
/// slack of a taller card falls at the bottom instead of being split.
EdgeInsetsGeometry dashboardSummaryCardPadding(DashboardDensity density) =>
    switch (density) {
      DashboardDensity.standard => const EdgeInsetsDirectional.fromSTEB(
        24,
        24,
        24,
        12,
      ),
      DashboardDensity.compact || DashboardDensity.mobile =>
        const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 10),
    };

double dashboardCardRadius(DashboardDensity density) => density.isDesktop
    ? DashboardCorner.desktopCard
    : DashboardCorner.mobileCard;

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    this.padding,
    this.onTap,
    this.semanticLabel,
    this.clipBehavior = Clip.none,
    required this.child,
  });

  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Off by default so a control swelling under an [ElasticPress] can paint
  /// past the card's edge; only a card whose own content bleeds clips.
  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final shape = AppShape.all(dashboardCardRadius(density));
    final content = Padding(
      padding: padding ?? dashboardCardPadding(density),
      child: child,
    );
    // Loon floats a card on nothing but its shadow — no border, no inner
    // highlight — and keeps that shadow in every appearance and every focus
    // state. Dropping it over the frost made the card dissolve into the pane
    // instead of sitting on it.
    final body = Material(
      type: MaterialType.transparency,
      child: onTap == null
          ? content
          : FocusRing(
              shape: shape,
              child: InkWell(
                customBorder: shape,
                onTap: onTap,
                child: content,
              ),
            ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(
          color: DashboardColors.of(context).card,
          shape: shape,
          shadows: DashboardShadows.card(context),
        ),
        child: body,
      ),
    );
  }
}

class DashboardCardHeader extends StatelessWidget {
  const DashboardCardHeader({
    super.key,
    this.glyph,
    required this.title,
    this.leading = const [],
    this.trailing = const [],
    this.chevron = false,
  });

  static const height = 24.0;
  static const glyphSize = 18.0;

  final Glyph? glyph;
  final String title;

  /// Sits right after the title, before the space that pushes [trailing] out.
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;
    final style = mobile
        ? DashboardText.mobileCardTitle(context)
        : DashboardText.cardTitle(context);
    final end = [
      ...trailing,
      if (chevron)
        GlyphIcon(
          AppGlyphs.chevronForward,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
    ];
    final start = Row(
      spacing: 8,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        ...leading,
      ],
    );
    return SizedBox(
      height: (mobile ? 26 : height) * scale,
      child: Row(
        spacing: 8,
        children: [
          if (glyph case final glyph?)
            GlyphIcon(glyph, size: glyphSize, color: iconColor),
          Expanded(
            child: end.isEmpty
                ? start
                : DashboardCappedRow(
                    start: start,
                    end: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: end,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Cut short past [_minScale]: an IPv6 address shrunk any further is unreadable.
class DashboardFitText extends StatelessWidget {
  const DashboardFitText(this.text, {super.key, required this.style});

  static const _minScale = 0.75;

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = globalState.measure
            .computeTextSize(Text(text, style: style))
            .width;
        if (width * _minScale <= constraints.maxWidth) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(text, maxLines: 1, style: style),
          );
        }
        return TooltipText(
          text: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
      },
    );
  }
}

/// Lays [end] out first at its own width, up to [share] of the row and scaled
/// down past that, so long translations or large text never overflow; [start]
/// takes what is left.
class DashboardCappedRow extends StatelessWidget {
  const DashboardCappedRow({
    super.key,
    required this.start,
    required this.end,
    this.share = 0.5,
    this.spacing = 8,
  });

  final Widget start;
  final Widget end;
  final double share;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        spacing: spacing,
        children: [
          Expanded(child: start),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(0, constraints.maxWidth - spacing) * share,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                height: constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : null,
                child: end,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _connectedSelectDuration = Duration(milliseconds: 240);

/// A row of [DashboardConnectedButton]s; the one pressed last paints on top.
class DashboardConnectedGroup extends StatelessWidget {
  const DashboardConnectedGroup({
    super.key,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    required this.children,
  });

  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _RaisedRow(
      crossAxisAlignment: crossAxisAlignment,
      spacing: 3,
      children: children,
    );
  }
}

class _RaisedRow extends Flex {
  const _RaisedRow({
    super.crossAxisAlignment,
    super.spacing,
    required super.children,
  }) : super(direction: Axis.horizontal);

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _RenderRaisedRow(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: clipBehavior,
      spacing: spacing,
    );
  }
}

class _RenderRaisedRow extends RenderFlex {
  _RenderRaisedRow({
    super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
  });

  RenderBox? _raised;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent) {
      return;
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final offset = (child.parentData! as FlexParentData).offset;
      if ((offset & child.size).contains(entry.localPosition)) {
        if (child != _raised) {
          _raised = child;
          markNeedsPaint();
        }
        return;
      }
    }
  }

  @override
  void dropChild(RenderObject child) {
    if (child == _raised) {
      _raised = null;
    }
    super.dropChild(child);
  }

  @override
  void defaultPaint(PaintingContext context, Offset offset) {
    void paint(RenderBox child) => context.paintChild(
      child,
      (child.parentData! as FlexParentData).offset + offset,
    );
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child != _raised) {
        paint(child);
      }
    }
    if (_raised case final raised?) {
      paint(raised);
    }
  }
}

/// M3 Expressive connected buttons: the ends round off the group, the inner
/// corners stay tight, and the selected one turns into a full pill. Each one
/// swells under a press.
class DashboardConnectedButton extends StatelessWidget {
  const DashboardConnectedButton({
    super.key,
    required this.selected,
    required this.first,
    required this.last,
    required this.outer,
    required this.inner,
    required this.background,
    required this.onTap,
    required this.semanticLabel,
    this.selectedColor,
    this.selectedForeground,
    required this.builder,
  });

  final bool selected;
  final bool first;
  final bool last;
  final double outer;
  final double inner;
  final Color background;

  /// What the button fills with once it is on; the app's tint by default.
  final Color? selectedColor;
  final Color? selectedForeground;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget Function(Color foreground) builder;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final startRest = first ? outer : inner;
    final endRest = last ? outer : inner;
    final colorScheme = context.colorScheme;
    final selectedColor = this.selectedColor ?? colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: ElasticPress(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 1 : 0),
          duration: context.motionDuration(_connectedSelectDuration),
          curve: Curves.easeOutCubic,
          builder: (context, amount, child) {
            final start = lerpDouble(startRest, outer, amount)!;
            final end = lerpDouble(endRest, outer, amount)!;
            final shape = AppShape.of(
              BorderRadius.horizontal(
                left: Radius.circular(rtl ? end : start),
                right: Radius.circular(rtl ? start : end),
              ),
            );
            return FocusRing(
              shape: shape,
              standsOff: selected,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: Color.lerp(background, selectedColor, amount),
                  shape: shape,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    customBorder: shape,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    onTap: onTap,
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: builder(
            selected
                ? selectedForeground ?? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

enum DashboardChipTone { idle, ok, warn }

/// Loon's status badge: 18 high and hard-coded at that height, a 5 corner, a
/// 10 pt medium label, and its colour carried as an 8% wash instead of a
/// filled container — the same whisper step as the shadow. [large] steps the
/// same badge up for the outbound detail sheet, where a 24 pt chip matches the
/// rows around it.
class DashboardChip extends StatelessWidget {
  const DashboardChip({
    super.key,
    required this.label,
    this.tone = DashboardChipTone.idle,
    this.dot = false,
    this.large = false,
  });

  static const height = DashboardMaterial.badgeHeight;
  static const largeHeight = 24.0;

  final String label;
  final DashboardChipTone tone;
  final bool dot;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = switch (tone) {
      DashboardChipTone.idle => colorScheme.onSurfaceVariant,
      DashboardChipTone.ok => colorScheme.success,
      DashboardChipTone.warn => colorScheme.warning,
    };
    final height = large ? largeHeight : DashboardChip.height;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 6),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: DashboardMaterial.whisperAlpha),
        shape: AppShape.all(DashboardCorner.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          if (dot)
            DecoratedBox(
              decoration: ShapeDecoration(
                color: color,
                shape: AppShape.circle,
              ),
              child: const SizedBox.square(dimension: 5),
            ),
          Text(
            label,
            maxLines: 1,
            style: DashboardText.badge(context, color: color, large: large),
          ),
        ],
      ),
    );
  }
}

/// Loon's segmented control: one recessed track, and the chosen segment is a
/// *darker* well inside it whose label takes the accent colour — not a filled
/// pill in the accent colour, which is what the connected-button group was.
///
/// Measured off its window: the track sits ~27 levels below the card, the well
/// ~8 above the track and warmed by roughly an eighth of the selection colour,
/// and only the chosen segment shows a glyph. Those three numbers are
/// [DashboardMaterial.trackAlpha], [DashboardMaterial.segmentAlpha] and the
/// label colour below.
class DashboardSegmented<T> extends StatelessWidget {
  const DashboardSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.onSelected,
    required this.labelOf,
    required this.glyphOf,
    this.height = 28,
  });

  final List<T> items;
  final T value;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final Glyph Function(T) glyphOf;
  final double height;

  /// The well has to clear the track by a hair on every side or the two read
  /// as one shape — measured at 2.6 on Loon's 28pt control, so a hairline.
  static const _inset = 2.5;

  @override
  Widget build(BuildContext context) {
    // Loon's track corner sweeps about 0.28 of the control's height. [AppShape]
    // draws a squircle, whose corner only reaches ~0.8 of the radius it is
    // handed, so the parameter runs higher than the corner it draws; 0.34 lands
    // on the same arc.
    final radius = height * 0.34;
    return Container(
      height: height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: DashboardMaterial.trackAlpha),
        shape: AppShape.all(radius),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _DashboardSegment(
                selected: item == value,
                label: labelOf(item),
                glyph: glyphOf(item),
                radius: math.max(0, radius - _inset),
                onTap: () => onSelected(item),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loon's accent is a deep saturated orange. The scheme's warning role is the
/// same colour family but a pale apricot — it reads as cream on a dark well,
/// where Loon's label pops. Pulling the lightness down and the saturation up
/// recovers that without hard-coding a hex the theme would ignore.
Color _selectionAccent(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation(math.max(hsl.saturation, 0.9))
      .withLightness(math.min(hsl.lightness, 0.56))
      .toColor();
}

class _DashboardSegment extends StatelessWidget {
  const _DashboardSegment({
    required this.selected,
    required this.label,
    required this.glyph,
    required this.radius,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Glyph glyph;
  final double radius;
  final VoidCallback onTap;

  static const _glyphSize = 13.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // Loon's selection colour is its warm accent, which is also the colour the
    // home grid already uses for the proxy side of every legend; the scheme's
    // primary is a desaturated blue in the default theme and turns the well
    // grey, so the accent comes from the warning role instead. The fill takes
    // the *container* tone: the plain warning is a pale apricot that lifts the
    // well 15 levels off the track where Loon only lifts it eight, while the
    // container lands within a level or two of Loon's measured well.
    final accent = _selectionAccent(colorScheme.warning);
    final wellColor = colorScheme.warningContainer.withValues(
      alpha: DashboardMaterial.segmentAlpha,
    );
    final foreground = selected ? accent : colorScheme.onSurfaceVariant;
    final shape = AppShape.all(radius);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motionDuration(const Duration(milliseconds: 180)),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: selected ? wellColor : Colors.transparent,
          shape: shape,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  if (selected)
                    GlyphIcon(glyph, size: _glyphSize, color: foreground),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context, emphasized: selected)
                          .copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A block inside a card, one tone off the card itself.
class DashboardBlock extends StatelessWidget {
  const DashboardBlock({
    super.key,
    required this.radius,
    this.color,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.semanticLabel,
    required this.child,
  });

  final double radius;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = AppShape.all(radius);
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: ShapeDecoration(
        color: color ?? DashboardColors.of(context).tone,
        shape: shape,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: Semantics(
                button: true,
                label: semanticLabel,
                child: FocusRing(
                  shape: shape,
                  child: InkWell(
                    customBorder: shape,
                    onTap: onTap,
                    child: content,
                  ),
                ),
              ),
            ),
    );
  }
}

/// An M3 Expressive shape, filled, with [child] centered on it.
class ShapeBadge extends StatelessWidget {
  const ShapeBadge({
    super.key,
    required this.shape,
    required this.color,
    required this.size,
    this.rotation = 0,
    this.ring,
    this.child,
  });

  final RoundedPolygon shape;
  final Color color;
  final double size;

  /// Turns the shape alone, leaving [child] upright.
  final double rotation;
  final BorderSide? ring;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ShapePainter(
        path: shapePathOf(shape),
        color: color,
        rotation: rotation,
        ring: ring,
      ),
      child: SizedBox.square(
        dimension: size,
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

final _shapePaths = Expando<Path>();

Path shapePathOf(RoundedPolygon shape) => _shapePaths[shape] ??= shape.toPath();

/// Paints a path laid out in the unit square, the space [MaterialShapes]
/// are normalized to.
class ShapePainter extends CustomPainter {
  const ShapePainter({
    required this.path,
    required this.color,
    this.rotation = 0,
    this.ring,
  });

  final Path path;
  final Color color;
  final double rotation;
  final BorderSide? ring;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(rotation)
      ..scale(size.width, size.height)
      ..translate(-0.5, -0.5)
      ..drawPath(path, Paint()..color = color);
    if (ring case final ring?) {
      strokeUnitShape(canvas, path, size.width, ring);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShapePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.rotation != rotation ||
      oldDelegate.ring != ring;
}

/// Strokes [side] along a unit-square [path] drawn at [extent], placing it by
/// [BorderSide.strokeAlign] with a scale about the center rather than an offset.
void strokeUnitShape(Canvas canvas, Path path, double extent, BorderSide side) {
  final scale = 1 + side.width * side.strokeAlign / extent;
  canvas
    ..save()
    ..translate(0.5, 0.5)
    ..scale(scale)
    ..translate(-0.5, -0.5)
    ..drawPath(path, side.toPaint()..strokeWidth = side.width / extent / scale)
    ..restore();
}

class DashboardSwitch extends StatelessWidget {
  const DashboardSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  /// A switch lays out past its track, which would set every row's height.
  static const trackWidth = CommonSwitch.trackWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: trackWidth,
      height: CommonSwitch.trackHeight,
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: CommonSwitch(
          value: value,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

/// A row holding one setting behind a switch: a cookie-6 icon container while
/// it is on, a plain circle while it is off.
class DashboardSwitchRow extends StatelessWidget {
  const DashboardSwitchRow({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.iconSize,
    required this.padding,
    required this.radius,
    this.color,
    this.onTap,
    this.showIcon = true,
  });

  final Glyph glyph;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final bool showIcon;

  static const _gap = 12.0;

  /// Whether each of [titles] fits beside the icon in rows [width] wide, so
  /// sibling rows can drop their icons together before a title is cut short.
  static bool iconFits(
    BuildContext context, {
    required double width,
    required double iconSize,
    required EdgeInsetsGeometry padding,
    required Iterable<String> titles,
  }) {
    final style = DashboardText.rowTitle(context);
    final room =
        width -
        padding.horizontal -
        iconSize -
        _gap * 2 -
        DashboardSwitch.trackWidth;
    return titles.every(
      (title) =>
          globalState.measure
              .computeTextSize(Text(title, style: style))
              .width <=
          room,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final glyphSize = iconSize * 0.5;
    return DashboardBlock(
      radius: radius,
      color: color,
      padding: padding,
      onTap: onTap,
      semanticLabel: title,
      child: Row(
        spacing: _gap,
        children: [
          if (showIcon)
            AnimatedSwitcher(
              duration: context.motionDuration(commonDuration),
              child: value
                  ? ShapeBadge(
                      key: const ValueKey(true),
                      shape: MaterialShapes.cookie6Sided,
                      color: colorScheme.primary,
                      size: iconSize,
                      child: GlyphIcon(
                        glyph,
                        size: glyphSize,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : ShapeBadge(
                      key: const ValueKey(false),
                      shape: MaterialShapes.circle,
                      color: colors.card,
                      size: iconSize,
                      child: GlyphIcon(
                        glyph,
                        size: glyphSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
              ],
            ),
          ),
          DashboardSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: title,
          ),
        ],
      ),
    );
  }
}

/// The last [height] dp of a list that runs past its card fade out instead of
/// showing a scroll bar.
class DashboardFadeOut extends StatelessWidget {
  const DashboardFadeOut({super.key, required this.child});

  static const height = 44.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final stop = bounds.height <= 0
            ? 1.0
            : ((bounds.height - height) / bounds.height).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, stop, 1],
        ).createShader(bounds);
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}

class DashboardIconButton extends StatelessWidget {
  const DashboardIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
  });

  static const size = 32.0;
  static const glyphSize = 18.0;

  final Glyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // Loon's icon buttons take the same 8% wash under the pointer as a badge
    // takes as its fill, so hover and press never introduce a fourth weight.
    final whisper = colorScheme.onSurfaceVariant.withValues(
      alpha: DashboardMaterial.whisperAlpha,
    );
    // A 24 tall card header would otherwise squeeze the circle into a pill.
    return SizedBox(
      width: size,
      child: OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        minHeight: size,
        maxHeight: size,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: glyphSize,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(size),
            fixedSize: const Size.square(size),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: colorScheme.onSurfaceVariant,
            overlayColor: whisper,
          ),
          onPressed: onPressed,
          icon: GlyphIcon(glyph, size: glyphSize),
        ),
      ),
    );
  }
}
