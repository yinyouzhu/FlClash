import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'stat_bar.dart';
import 'traffic.dart';

const _minSpeedScale = 8 * 1024.0;

/// The two directions as a chart each, side by side, with a shared card and an
/// axis per chart so a glance reads an absolute speed, not just a shape.
///
/// Measured off Loon's own card: the dot and its label head the panel, the
/// figure sits under them with its unit in the same white rather than as a
/// footnote, and the chart runs to the card's bottom edge with the axis
/// printed down its side. Nothing separates the halves but air.
class SpeedOverviewCard extends ConsumerWidget {
  const SpeedOverviewCard({super.key});

  static const _panelGap = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffics = ref.watch(trafficsProvider);
    final latest = traffics.list.safeLast(const Traffic());
    return DashboardCard(
      semanticLabel: context.appLocalizations.networkSpeed,
      clipBehavior: Clip.antiAlias,
      // The axis prints its last tick on the baseline, so the bottom inset
      // holds the half of that label that hangs below the curve.
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _panelGap,
        children: [
          for (final direction in TrafficDirection.values)
            Expanded(
              child: _SpeedPanel(
                direction: direction,
                traffics: traffics,
                speed: direction.of(latest),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({
    required this.direction,
    required this.traffics,
    required this.speed,
  });

  static const _tickCount = 5;
  static const _axisWidth = 50.0;
  static const _axisGap = 6.0;

  /// The axis label's line box. A tick prints with its centre on the grid line
  /// and hangs half a line past the chart's top and bottom, which is what
  /// keeps the numbers level with the lines they name.
  static const _axisLineHeight = 14.0;

  final TrafficDirection direction;
  final FixedList<Traffic> traffics;
  final num speed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final show = speed.traffic;
    final axisMax = _axisMaxOf(traffics, direction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 6,
          children: [
            DashboardLegendDot(color: direction.colorOf(context), size: 9),
            Flexible(
              child: Text(
                direction.labelOf(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.speedLabel(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: show.value,
                style: DashboardText.speedFigure(context),
              ),
              TextSpan(
                text: ' ${show.unit}/s',
                style: DashboardText.speedUnit(context),
              ),
            ],
          ),
          maxLines: 1,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _axisWidth,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < _tickCount; i++)
                          Positioned(
                            top:
                                height * i / (_tickCount - 1) -
                                _axisLineHeight / 2,
                            // Left-aligned against the dot and the figure above,
                            // as Loon prints its scale: the ticks start on the
                            // panel's own margin instead of being pushed in by
                            // the widest one.
                            left: 0,
                            child: Text(
                              _axisLabel(
                                axisMax * (_tickCount - 1 - i) / (_tickCount - 1),
                              ),
                              maxLines: 1,
                              style: DashboardText.speedAxis(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _axisGap),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TickGridPainter(
                              ticks: _tickCount,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: LineChart(
                            values: [
                              for (final traffic in traffics.list)
                                direction.of(traffic).toDouble(),
                            ],
                            revision: traffics.revision,
                            capacity: traffics.maxLength,
                            minScale: _minSpeedScale,
                            maxValue: axisMax,
                            color: direction.colorOf(context),
                            baselineRatio: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The window's peak, rounded up to a top the four grid lines divide evenly.
///
/// Rounding the top itself to a "nice" number gives ticks nobody would say —
/// a 4.8 MB/s peak landed on 5 and printed 3.8 and 1.3 down the side. Rounding
/// the *step* instead, then multiplying it by four, keeps every tick a value
/// worth reading while still leaving the curve headroom.
double _axisMaxOf(FixedList<Traffic> traffics, TrafficDirection direction) {
  var peak = 0.0;
  for (final traffic in traffics.list) {
    peak = math.max(peak, direction.of(traffic).toDouble());
  }
  return math.max(_niceUnit(peak / 4) * 4, _minSpeedScale);
}

/// The smallest readable step at or above [value]: 1, 1.5, 2 … 8 of whatever
/// its own decade is, in the byte's 1024 steps so a tick lands on kB or MB
/// rather than on a fraction of one.
double _niceUnit(double value) {
  if (value <= 0) {
    return _minSpeedScale / 4;
  }
  var unit = 1.0;
  while (value / unit >= 1024) {
    unit *= 1024;
  }
  var decade = 1.0;
  while (value / unit / decade >= 10) {
    decade *= 10;
  }
  final normalized = value / unit / decade;
  for (final step in _niceSteps) {
    if (normalized <= step) {
      return step * decade * unit;
    }
  }
  return 10 * decade * unit;
}

const _niceSteps = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];

final _trailingZero = RegExp(r'\.0+$');

String _axisLabel(num bytes) {
  final show = bytes.traffic;
  return '${show.value.replaceAll(_trailingZero, '')}${show.unit}/s';
}

class _TickGridPainter extends CustomPainter {
  const _TickGridPainter({required this.ticks, required this.color});

  static const _alpha = 0.22;
  static const _dash = 3.5;
  static const _gap = 4.5;

  final int ticks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: _alpha)
      ..strokeWidth = 1;
    for (var i = 0; i < ticks; i++) {
      final y = (size.height * i / (ticks - 1)).clamp(0.5, size.height - 0.5);
      // Dashed, as Loon draws them: a solid rule behind the curve competes
      // with it, where a broken one reads as the scale it is.
      for (var x = 0.0; x < size.width; x += _dash + _gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + _dash, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TickGridPainter oldDelegate) =>
      oldDelegate.ticks != ticks || oldDelegate.color != color;
}
