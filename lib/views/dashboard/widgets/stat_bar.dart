import 'dart:math' as math;

import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:material_ui/material_ui.dart';

/// One rounded track split in proportion, the way a traffic or connection
/// card shows its parts.
///
/// Loon draws the row as a single capsule and clips what it holds: the first
/// segment carries the round left end, the last the round right end, and every
/// seam in between stays square. Rounding each segment on its own turned the
/// bar into three pills, which read as separate measures rather than one.
class DashboardStatBar extends StatelessWidget {
  const DashboardStatBar({
    super.key,
    required this.segments,
    this.height = 6.5,
  });

  final List<(num, Color)> segments;
  final double height;

  /// Loon leaves 5 px at 2.07 px/pt between segments — about 2.5 pt.
  static const _gap = 2.5;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final segment in segments)
        if (segment.$1 > 0) segment,
    ];
    final total = visible.fold<num>(0, (sum, segment) => sum + segment.$1);
    if (total <= 0) {
      return _Bar(height: height, color: DashboardColors.of(context).track);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = math.max(
          0,
          constraints.maxWidth - _gap * (visible.length - 1),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _gap,
              children: [
                for (final (value, color) in visible)
                  SizedBox(
                    width: room * (value / total),
                    child: ColoredBox(color: color),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: AppShape.full),
      ),
    );
  }
}

class DashboardLegendDot extends StatelessWidget {
  const DashboardLegendDot({
    super.key,
    required this.color,
    this.size = defaultSize,
  });

  /// Loon's dot measures 14 px at 2.07 px/pt — 7 pt across. A chart's own
  /// legend draws it a size up, since it heads a panel instead of annotating
  /// a bar.
  static const defaultSize = 7.0;

  final Color color;

  /// Overrides [defaultSize] where the dot scales with what it labels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: AppShape.circle),
      ),
    );
  }
}

/// Loon's legend entry: a dot, its label, and the value under the label.
///
/// The value starts at the label's own left edge rather than at the dot's, so
/// the two lines read as one block with the dot hanging to their left. Sharing
/// a left edge with the dot, as we did before, made the number look like a
/// second column instead of the label's own reading.
class DashboardLegendItem extends StatelessWidget {
  const DashboardLegendItem({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The dot is centred on the label's line, not on the whole entry.
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: DashboardLegendDot(color: color),
        ),
        const SizedBox(width: 6.5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.legendLabel(context),
              ),
              const SizedBox(height: 1.5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.legendValue(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The gap between legend entries.
///
/// Loon does not pack them edge to edge: at its own width the three columns
/// start 86.5 pt apart inside a 223 pt row, and the two-column card starts its
/// second entry 132 pt in inside 228 pt. Both fall out of one 36 pt gutter —
/// which is why the entries read as evenly spread rather than bunched left.
double legendSpacing(BuildContext context) =>
    DashboardDensityScope.of(context).isDesktop ? 36 : 20;
