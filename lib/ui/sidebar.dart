import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:fl_clash/ui/context.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/l10n.dart';
import 'package:fl_clash/ui/scroll_behavior.dart';
import 'package:fl_clash/ui/shape.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:fl_clash/ui/typography.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const _compactWidth = 48.0;
/// Loon's expanded rail measures 149 across, which is what puts its content
/// column — and therefore every card on the home grid — on the same x as ours.
const _expandedWidth = 149.0;
const _expandedSideInset = 10.0;
const _itemSize = 40.0;
const _itemGap = 8.0;
const _verticalInset = 4.0;
const _maxSideInset = 12.0;
const _iconSize = 24.0;
const _labelGap = 10.0;
const _labelTrailing = 8.0;
const _brandGap = 18.0;
const _brandLogoSize = 28.0;
const _brandTextGap = 8.0;
const _brandEndInset = 10.0;
const _expandDuration = Duration(milliseconds: 250);
final _itemShape = AppShape.all(12);

class SidebarDestination {
  const SidebarDestination({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;
}

/// Where the sidebar cannot widen in place, [onToggle] is null and the toggle
/// opens the expanded pane over the content instead.
///
/// [windowControls] is the area native window buttons cover at the top start
/// corner; the pane keeps it clear and never gets narrower than it.
///
/// The brand block shows [title], [statusLabel] and [version]; the app supplies
/// them so the components stay clear of the app layer.
class NavigationSidebar extends StatefulWidget {
  const NavigationSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    this.onToggle,
    this.windowControls = Size.zero,
    this.title,
    this.statusLabel,
    this.connected = false,
    this.version,
  });

  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback? onToggle;
  final Size windowControls;
  final String? title;
  final String? statusLabel;
  final bool connected;
  final String? version;

  @override
  State<NavigationSidebar> createState() => _NavigationSidebarState();
}

class _NavigationSidebarState extends State<NavigationSidebar>
    with SingleTickerProviderStateMixin {
  final _overlayController = OverlayPortalController();
  late final AnimationController _overlayExpansion = AnimationController(
    vsync: this,
    duration: _expandDuration,
  );
  late final CurvedAnimation _overlayProgress = CurvedAnimation(
    parent: _overlayExpansion,
    curve: Easing.standard,
  );

  @override
  void didUpdateWidget(covariant NavigationSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle != null && _overlayController.isShowing) {
      _overlayExpansion.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideIfDismissed());
    }
  }

  void _handleToggle() {
    final onToggle = widget.onToggle;
    if (onToggle != null) {
      onToggle();
    } else if (_overlayExpansion.isForwardOrCompleted) {
      _closeOverlay();
    } else {
      _overlayController.show();
      _overlayExpansion.forward();
    }
  }

  void _closeOverlay() {
    _overlayExpansion.reverse().whenCompleteOrCancel(_hideIfDismissed);
  }

  void _hideIfDismissed() {
    if (mounted && _overlayExpansion.isDismissed) {
      _overlayController.hide();
    }
  }

  @override
  void dispose() {
    _overlayProgress.dispose();
    _overlayExpansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlayController,
      overlayChildBuilder: (context, info) {
        return _SidebarOverlay(
          anchor: MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          ),
          overlayWidth: info.overlaySize.width,
          progress: _overlayProgress,
          onDismiss: _closeOverlay,
          builder: (progress) => Padding(
            padding: safePadding,
            child: _SidebarPane(
              progress: progress,
              windowControls: widget.windowControls,
              expanded: true,
              destinations: widget.destinations,
              selectedIndex: widget.selectedIndex,
              onSelected: (index) {
                widget.onSelected(index);
                _closeOverlay();
              },
              onToggle: _closeOverlay,
              title: widget.title,
              statusLabel: widget.statusLabel,
              connected: widget.connected,
              version: widget.version,
            ),
          ),
        );
      },
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.expanded ? 1.0 : 0.0),
          duration: _expandDuration,
          curve: Easing.standard,
          builder: (context, progress, _) => _SidebarPane(
            progress: progress,
            windowControls: widget.windowControls,
            expanded: widget.expanded,
            destinations: widget.destinations,
            selectedIndex: widget.selectedIndex,
            onSelected: widget.onSelected,
            onToggle: _handleToggle,
            title: widget.title,
            statusLabel: widget.statusLabel,
            connected: widget.connected,
            version: widget.version,
          ),
        ),
      ),
    );
  }
}

class _SidebarOverlay extends StatelessWidget {
  const _SidebarOverlay({
    required this.anchor,
    required this.overlayWidth,
    required this.progress,
    required this.onDismiss,
    required this.builder,
  });

  final Rect anchor;
  final double overlayWidth;
  final Animation<double> progress;
  final VoidCallback onDismiss;
  final Widget Function(double progress) builder;

  @override
  Widget build(BuildContext context) {
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final colorScheme = context.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: isLtr ? anchor.left : null,
          right: isLtr ? null : overlayWidth - anchor.right,
          top: anchor.top,
          height: anchor.height,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    onDismiss();
                    return null;
                  },
                ),
              },
              child: FocusScope(
                autofocus: true,
                child: Material(
                  color: colorScheme.chromeSurface,
                  shape: BorderDirectional(
                    end: Divider.createBorderSide(context),
                  ),
                  elevation: 8,
                  shadowColor: colorScheme.shadow,
                  child: AnimatedBuilder(
                    animation: progress,
                    builder: (_, _) => builder(progress.value),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarColors {
  _SidebarColors(ColorScheme scheme)
    : selectedFill = scheme.primary.withValues(alpha: 0.12),
      label = scheme.onSurface,
      selectedLabel = scheme.primary,
      icon = scheme.onSurfaceVariant,
      selectedIcon = scheme.primary,
      overlay = WidgetStateProperty.fromMap({
        WidgetState.pressed: scheme.onSurface.withValues(alpha: 0.06),
        WidgetState.focused: scheme.onSurface.withValues(alpha: 0.1),
        WidgetState.hovered: scheme.onSurface.withValues(alpha: 0.04),
        WidgetState.any: Colors.transparent,
      });

  final Color selectedFill;
  final Color label;
  final Color selectedLabel;
  final Color icon;
  final Color selectedIcon;
  final WidgetStateProperty<Color> overlay;
}

class _SidebarPane extends StatelessWidget {
  const _SidebarPane({
    required this.progress,
    required this.windowControls,
    required this.expanded,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onToggle,
    this.title,
    this.statusLabel,
    this.connected = false,
    this.version,
  });

  final double progress;
  final Size windowControls;
  final bool expanded;
  final List<SidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggle;
  final String? title;
  final String? statusLabel;
  final bool connected;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final colors = _SidebarColors(context.colorScheme);
    final fontSize = AppTextStyle.subheadline.size;
    final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final compactWidth = math.max(_compactWidth, windowControls.width);
    final sideInset = math.min(_maxSideInset, (compactWidth - _itemSize) / 2);
    final expandedInset = math.max(sideInset, _expandedSideInset);
    final rowInset = lerpDouble(sideInset, expandedInset, progress)!;
    final itemWidth = compactWidth - sideInset * 2;
    final iconInset = (itemWidth - _iconSize) / 2;
    final itemHeight =
        _itemSize + MediaQuery.textScalerOf(context).scale(fontSize) - fontSize;
    final rowWidth = _expandedWidth - expandedInset * 2;
    final labelStyle = AppTextStyle.subheadline
        .of(context)
        .copyWith(color: colors.label);
    final labelWidth =
        rowWidth - iconInset - _iconSize - _labelGap - _labelTrailing;
    String rowTooltip(String label) =>
        expanded &&
            progress == 1 &&
            _fitsOneLine(context, label, labelStyle, labelWidth)
        ? ''
        : label;
    return SizedBox(
      width: lerpDouble(compactWidth, _expandedWidth, progress),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: windowControls.height + _verticalInset),
          if (title != null) ...[
            _SidebarBrand(
              progress: progress,
              sideInset: lerpDouble(
                (compactWidth - _brandLogoSize) / 2,
                expandedInset + iconInset,
                progress,
              )!,
              title: title!,
              statusLabel: statusLabel,
              connected: connected,
            ),
            const SizedBox(height: _brandGap),
          ],
          Expanded(
            child: ScrollConfiguration(
              behavior: const HiddenBarScrollBehavior(),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, destination) in destinations.indexed)
                      _SidebarButton(
                        key: ValueKey(destination.label),
                        colors: colors,
                        height: itemHeight,
                        sideInset: rowInset,
                        selected: index == selectedIndex,
                        tooltip: rowTooltip(destination.label),
                        onTap: () => onSelected(index),
                        child: _DestinationRow(
                          destination: destination,
                          selected: index == selectedIndex,
                          width: rowWidth,
                          iconInset: iconInset,
                          style: labelStyle,
                          selectedColor: colors.selectedLabel,
                          labelOpacity: labelOpacity,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: _verticalInset),
          _SidebarButton(
            colors: colors,
            height: itemHeight,
            sideInset: rowInset,
            tooltip: expanded
                ? UiLocalizations.of(context).showLess
                : UiLocalizations.of(context).showMore,
            tooltipIsLabel: true,
            onTap: onToggle,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: rowWidth,
                maxWidth: rowWidth,
                child: Row(
                  children: [
                    SizedBox(width: iconInset),
                    GlyphIcon(AppGlyphs.sidebar(progress)),
                    const SizedBox(width: _labelGap),
                    Expanded(
                      child: Opacity(
                        opacity: labelOpacity,
                        alwaysIncludeSemantics: true,
                        child: ExcludeSemantics(
                          child: Text(
                            expanded
                                ? UiLocalizations.of(context).showLess
                                : UiLocalizations.of(context).showMore,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: _labelTrailing),
                  ],
                ),
              ),
            ),
          ),
          if (version != null)
            _SidebarVersion(
              progress: progress,
              version: version!,
              sideInset: expandedInset + iconInset,
            ),
          const SizedBox(height: _verticalInset),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    super.key,
    required this.colors,
    required this.height,
    required this.sideInset,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected,
    this.tooltipIsLabel = false,
  });

  final _SidebarColors colors;
  final double height;
  final double sideInset;
  final bool? selected;
  final String tooltip;
  final bool tooltipIsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sideInset,
        vertical: _itemGap / 2,
      ),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: FocusRing(
          shape: _itemShape,
          child: Material(
            color: selected == true ? colors.selectedFill : Colors.transparent,
            shape: _itemShape,
            child: InkWell(
              onTap: onTap,
              customBorder: _itemShape,
              mouseCursor: SystemMouseCursors.basic,
              splashFactory: NoSplash.splashFactory,
              overlayColor: colors.overlay,
              child: Tooltip(
                message: tooltip,
                excludeFromSemantics: !tooltipIsLabel,
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: _iconSize,
                    color: selected == true ? colors.selectedIcon : colors.icon,
                  ),
                  child: SizedBox(height: height, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _fitsOneLine(
  BuildContext context,
  String text,
  TextStyle? style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: width);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

/// The row lays out at the expanded width whatever the pane's current width,
/// so the label is clipped rather than reflowed while the pane animates.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.width,
    required this.iconInset,
    required this.style,
    required this.selectedColor,
    required this.labelOpacity,
  });

  final SidebarDestination destination;
  final bool selected;
  final double width;
  final double iconInset;
  final TextStyle? style;
  final Color selectedColor;
  final double labelOpacity;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: width,
        maxWidth: width,
        child: Row(
          children: [
            SizedBox(width: iconInset),
            AnimatedGlyph(glyph: destination.glyph, filled: selected),
            const SizedBox(width: _labelGap),
            Expanded(
              child: Opacity(
                opacity: labelOpacity,
                alwaysIncludeSemantics: true,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: selected
                      ? style!.copyWith(color: selectedColor)
                      : style,
                ),
              ),
            ),
            const SizedBox(width: _labelTrailing),
          ],
        ),
      ),
    );
  }
}

/// The brand block at the top of the pane: the app mark, name, and a live
/// connection dot, the way Loon pairs its balloon with "Loon" and "已连接".
/// The name and status fade out as the pane collapses to icons only.
class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.progress,
    required this.sideInset,
    required this.title,
    required this.connected,
    this.statusLabel,
  });

  final double progress;
  final double sideInset;
  final String title;
  final bool connected;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final labelOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    final statusColor = connected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final statusText = statusLabel;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: sideInset,
        end: _brandEndInset,
        top: 6,
        bottom: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/icon.png',
            width: _brandLogoSize,
            height: _brandLogoSize,
          ),
          SizedBox(width: _brandTextGap * progress),
          Expanded(
            child: Opacity(
              opacity: labelOpacity,
              alwaysIncludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (statusText != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(color: statusColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The version line at the foot of the pane, mirroring Loon's "vX.Y.Z".
class _SidebarVersion extends StatelessWidget {
  const _SidebarVersion({
    required this.progress,
    required this.version,
    required this.sideInset,
  });

  final double progress;
  final String version;
  final double sideInset;

  @override
  Widget build(BuildContext context) {
    final opacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sideInset, vertical: 4),
        child: Text(
          version,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(
                color: context.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
        ),
      ),
    );
  }
}
