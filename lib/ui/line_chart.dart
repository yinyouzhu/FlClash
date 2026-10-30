import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.revision,
    required this.capacity,
    required this.minScale,
    required this.color,
    required this.baselineRatio,
    this.maxValue,
  }) : assert(capacity > 1),
       assert(minScale > 0);

  final List<double> values;

  /// Pins the top of the chart to this value instead of fitting the curve, so
  /// an axis drawn beside it keeps telling the truth between frames.
  final double? maxValue;

  /// Advances by one for each sample appended to [values]. Any other change,
  /// such as a clear, starts the chart over.
  final int revision;

  final int capacity;

  /// The least value the top stands for, so idle noise stays near the baseline.
  final double minScale;

  final Color color;

  /// Where the zero line sits, as a share of the height from the top.
  final double baselineRatio;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart>
    with SingleTickerProviderStateMixin {
  /// One sample per second is what the Core reports at, so that is the span
  /// the curve takes to slide a column.
  static const _interval = Duration(seconds: 1);

  /// A stalled frame — a hidden window, a heavy rebuild — must not hand the
  /// ticker a gap big enough to spend the whole slide at once.
  static const _maxFrame = Duration(milliseconds: 120);

  late _Series _series;

  late final Ticker _ticker;

  /// Columns still owed to the curve, in samples. Appending one adds a column;
  /// the ticker spends it back over the second that sample stands for, so the
  /// new point eases in from past the right edge instead of every point
  /// jumping a column at the once-a-second update. Without this the chart only
  /// moves in steps, which reads as stiff however the line is drawn.
  final _shift = ValueNotifier<double>(0);

  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _series = _Series.of(widget.values, _seriesLength);
    _ticker = createTicker(_tick);
  }

  int get _seriesLength => widget.capacity + 1;

  @override
  void didUpdateWidget(LineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appended = widget.revision - oldWidget.revision;
    if (widget.capacity != oldWidget.capacity ||
        appended < 0 ||
        appended > widget.values.length) {
      _series = _Series.of(widget.values, _seriesLength);
      _shift.value = 0;
    } else if (appended > 0) {
      _series = _series.append(
        widget.values.sublist(widget.values.length - appended),
      );
      // The columns and the array move opposite ways: appending pushes every
      // existing point a column left, and this pushes the drawing a column
      // right, so what is on screen stays put and only the new point travels.
      _shift.value = math.min(_shift.value + appended, 3);
      _resume();
    }
  }

  /// Only runs while there is a column to spend: a ticker left running would
  /// keep the app producing frames at 60 Hz for a chart that is not moving.
  void _resume() {
    if (_ticker.isActive) {
      return;
    }
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final frame = elapsed - _lastTick;
    _lastTick = elapsed;
    final spent =
        (frame > _maxFrame ? _maxFrame : frame).inMicroseconds /
        _interval.inMicroseconds;
    final next = math.max(0.0, _shift.value - spent);
    _shift.value = next;
    if (next <= 0) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _LineChartPainter(
            series: _series,
            capacity: widget.capacity,
            minScale: widget.minScale,
            maxValue: widget.maxValue,
            color: widget.color,
            baselineRatio: widget.baselineRatio,
            shift: _shift,
          ),
        ),
      ),
    );
  }
}

@immutable
class _Series {
  const _Series._(this.values);

  factory _Series.of(List<double> window, int length) {
    final count = math.min(window.length, length);
    return _Series._(
      List.filled(length, 0.0)
        ..setAll(length - count, window.sublist(window.length - count)),
    );
  }

  final List<double> values;

  /// Drawn as read. A smoothed copy rounded off exactly the single-sample
  /// spikes a speed graph is made of, and Loon draws the samples themselves.
  List<double> get heights => values;

  _Series append(List<double> samples) {
    final next = [...values, ...samples];
    return _Series._(next.sublist(next.length - values.length));
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.capacity,
    required this.minScale,
    required this.maxValue,
    required this.color,
    required this.baselineRatio,
    required this.shift,
  }) : _strokePaint = Paint()
         ..color = color
         ..strokeWidth = _strokeWidth
         ..strokeCap = StrokeCap.round
         ..strokeJoin = StrokeJoin.round
         ..style = PaintingStyle.stroke,
       super(repaint: shift);

  /// Loon's own stroke measures about 2.6 pt across. At 2 the curve thins out
  /// against a dark panel and every corner reads as a scratch.
  static const _strokeWidth = 2.6;

  /// The wash under the line: strongest where it meets the line, still faintly
  /// there at the baseline. Loon keeps a floor under it rather than fading to
  /// nothing, which is what makes the area read as a filled shape instead of
  /// a line that happens to be thick.
  static const _fillAlpha = 0.30;
  static const _fillFloor = 0.04;

  final _Series series;
  final int capacity;
  final double minScale;
  final double? maxValue;
  final Color color;
  final double baselineRatio;

  /// Columns of a sample still to slide, owned by the state and spent by the
  /// ticker; the painter only reads it.
  final ValueListenable<double> shift;

  final Paint _strokePaint;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (capacity - 1);
    final baseline = size.height * baselineRatio;
    final heights = series.heights;
    final slide = shift.value * step;
    final firstX = size.width - (heights.length - 1) * step + slide;

    // Straight segments, as Loon draws them: a speed spike is a spike, and a
    // curve rounding it off reads as data we smoothed rather than measured.
    var x = firstX;
    var y = -heights[0];
    final curve = Path()..moveTo(x, y);
    for (var i = 1; i < heights.length; i++) {
      x += step;
      y = -heights[i];
      curve.lineTo(x, y);
    }
    final top = math
        .max(minScale, maxValue ?? -curve.getBounds().top)
        .toDouble();
    final yScale = (baseline - _strokeWidth) / top;
    final line = curve.transform(
      (Matrix4.identity()
            ..translateByDouble(0, baseline, 0, 1)
            ..scaleByDouble(1, yScale, 1, 1))
          .storage,
    );
    final area = Path.from(line)
      ..lineTo(x, size.height)
      ..lineTo(firstX, size.height)
      ..close();
    final fillTop = math.min(baseline, line.getBounds().top);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: color.a * _fillAlpha),
          color.withValues(alpha: color.a * _fillFloor * 4),
          color.withValues(alpha: color.a * _fillFloor),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(
        Rect.fromLTRB(
          math.min(firstX, 0),
          fillTop,
          math.max(x, size.width),
          math.max(baseline, fillTop + 1),
        ),
      );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawPath(area, fillPaint)
      ..drawPath(line, _strokePaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.capacity != capacity ||
        oldDelegate.minScale != minScale ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.color != color ||
        oldDelegate.baselineRatio != baselineRatio;
  }
}
