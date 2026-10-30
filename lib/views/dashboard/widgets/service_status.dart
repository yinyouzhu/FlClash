import 'dart:async';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/probe_start_hold.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

String _statusLabel(BuildContext context, ServiceProbeStatus status) {
  final localizations = context.appLocalizations;
  return switch (status) {
    ServiceProbeStatus.available => localizations.serviceAvailable,
    ServiceProbeStatus.restricted => localizations.serviceRestricted,
    ServiceProbeStatus.unavailable => localizations.serviceUnavailable,
    ServiceProbeStatus.disallowedIsp => localizations.serviceDisallowedIsp,
    ServiceProbeStatus.blocked => localizations.serviceBlocked,
    ServiceProbeStatus.unsupportedRegion =>
      localizations.serviceUnsupportedRegion,
    ServiceProbeStatus.originalsOnly => localizations.serviceOriginalsOnly,
    ServiceProbeStatus.comingSoon => localizations.serviceComingSoon,
    ServiceProbeStatus.timeout => localizations.timeout,
    ServiceProbeStatus.failed => localizations.serviceFailed,
  };
}

Color _statusColor(BuildContext context, ServiceProbeStatus status) {
  final colorScheme = context.colorScheme;
  return switch (status) {
    ServiceProbeStatus.available => colorScheme.success,
    ServiceProbeStatus.restricted ||
    ServiceProbeStatus.disallowedIsp ||
    ServiceProbeStatus.blocked ||
    ServiceProbeStatus.unsupportedRegion ||
    ServiceProbeStatus.originalsOnly ||
    ServiceProbeStatus.comingSoon => colorScheme.warning,
    ServiceProbeStatus.unavailable ||
    ServiceProbeStatus.timeout ||
    ServiceProbeStatus.failed => colorScheme.error,
  };
}

(String, Color) _statusOf(
  BuildContext context,
  ServiceCheck? check,
  ProbePhase phase,
) {
  final localizations = context.appLocalizations;
  final idle = context.colorScheme.onSurfaceVariant;
  if (phase == ProbePhase.probing) {
    return (localizations.loading, idle);
  }
  if (check != null) {
    return (
      _statusLabel(context, check.status),
      _statusColor(context, check.status),
    );
  }
  if (phase == ProbePhase.failed) {
    return (
      _statusLabel(context, ServiceProbeStatus.failed),
      context.colorScheme.error,
    );
  }
  return (localizations.servicePending, idle);
}

/// A service as the card shows it: a failure held through a start reads as
/// still checking, without the result it replaced.
class _ServiceView {
  _ServiceView(this.target, ProbeEntry<ServiceCheck> entry, this.phase)
    : check = phase == entry.phase ? entry.value : null;

  final ServiceTarget target;
  final ProbePhase phase;
  final ServiceCheck? check;

  bool get loading => phase == ProbePhase.probing && check == null;

  bool get abnormal => switch (check) {
    final check? => check.status != ServiceProbeStatus.available,
    null => phase == ProbePhase.failed,
  };

  /// What the row ends on: the delay the Core measured, or the word for
  /// whatever it answered instead.
  String valueOf(BuildContext context) => switch (check) {
    ServiceCheck(status: ServiceProbeStatus.available, :final delay) =>
      delay != null
          ? '${delay}ms'
          : _statusLabel(context, ServiceProbeStatus.available),
    final ServiceCheck check => _statusLabel(context, check.status),
    null => _statusOf(context, null, phase).$1,
  };

  (String, Color) statusOf(BuildContext context) => switch (check) {
    ServiceCheck(status: ServiceProbeStatus.available, :final delay) => (
      delay != null
          ? '${delay}ms'
          : _statusLabel(context, ServiceProbeStatus.available),
      context.colorScheme.onSurfaceVariant,
    ),
    final ServiceCheck check => (
      _statusLabel(context, check.status),
      _statusColor(context, check.status),
    ),
    null => _statusOf(context, null, phase),
  };

  Color? dotOf(BuildContext context) => switch (check) {
    final check? => _statusColor(context, check.status),
    null when phase == ProbePhase.failed => context.colorScheme.error,
    null => null,
  };
}

/// Three tones, one per thing the card can say: a service that answered
/// quickly, one that answered slowly, and one that did not answer at all. The
/// theme's success and warning are toned down for text and read pale next to
/// a dot this small.
const _goodInk = Color(0xFF34C759);
const _fairInk = Color(0xFFE0A020);
const _poorInk = Color(0xFFE5484D);

/// Past this a delay is worth an amber mark; below it the reading is fine.
const _slowDelay = 200;

Color _delayInk(int delay) => delay < _slowDelay ? _goodInk : _fairInk;

String _clockOf(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}:'
    '${time.second.toString().padLeft(2, '0')}';

class ServiceStatusCard extends ConsumerStatefulWidget {
  const ServiceStatusCard({super.key, this.columns = 2});

  /// Columns the desktop grid uses. The row count is fixed at [rows], so the
  /// card carries the eight services Loon's own card does.
  final int columns;

  static const rows = 4;
  static const mobileRows = 8;
  static const autoCheckInterval = Duration(seconds: 30);

  @override
  ConsumerState<ServiceStatusCard> createState() => _ServiceStatusCardState();
}

class _ServiceStatusCardState extends ConsumerState<ServiceStatusCard>
    with ProbeStartHold<ServiceStatusCard> {
  late final ServiceStatus _services;
  late final Timer _autoCheck;
  Set<ServiceTarget> _shown = const {};
  Set<ServiceTarget> _watched = const {};
  int? _shownCount;
  var _syncScheduled = false;
  DateTime? _sweepStartedAt;
  var _sweeping = false;
  DateTime? _sweptAt;
  Duration? _sweepDuration;

  @override
  void initState() {
    super.initState();
    _services = ref.read(serviceStatusProvider.notifier);
    // Loon re-checks on a timer rather than only when the route moves, which
    // is what keeps the numbers live on a window nobody is touching.
    _autoCheck = Timer.periodic(
      ServiceStatusCard.autoCheckInterval,
      (_) => _sweep(),
    );
  }

  @override
  void dispose() {
    _autoCheck.cancel();
    for (final target in _watched) {
      _services.unwatch(target);
    }
    super.dispose();
  }

  void _sweep({bool force = false}) {
    // A sweep of eight services can outlast the interval, and two of them
    // racing would each cancel the other's reading. A tap still gets through.
    if (!force && _sweepStartedAt != null) {
      return;
    }
    if (_watched.isEmpty || !ref.read(appVisibleProvider)) {
      return;
    }
    final targets = _watched.toList();
    final started = DateTime.now();
    // Only a sweep the user asked for spins the button: the ones on the timer
    // run every thirty seconds and would leave it turning most of the time.
    setState(() {
      _sweepStartedAt = started;
      _sweeping = force;
    });
    _services.refresh(targets);
    unawaited(_timeSweep(targets, started));
  }

  /// Waits for the sweep it started to land, then records how long it took.
  /// Polled rather than settled from a build: a window nobody touches draws
  /// no frames, and the reading would sit unrecorded until the next repaint.
  Future<void> _timeSweep(
    List<ServiceTarget> targets,
    DateTime started,
  ) async {
    final deadline = started.add(const Duration(seconds: 60));
    var sawLoading = false;
    while (mounted && _sweepStartedAt == started) {
      final state = ref.read(serviceStatusProvider);
      final loading = targets.any(state.isLoading);
      if (loading) {
        sawLoading = true;
      } else if (sawLoading) {
        break;
      }
      if (!loading && DateTime.now().isAfter(deadline)) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted || _sweepStartedAt != started) {
      return;
    }
    final landed = DateTime.now();
    setState(() {
      _sweptAt = landed;
      _sweepDuration = landed.difference(started);
      _sweepStartedAt = null;
      _sweeping = false;
    });
  }

  void _syncShown(Set<ServiceTarget> shown, int count) {
    if (setEquals(shown, _shown) && count == _shownCount) return;
    _shown = shown;
    _shownCount = count;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      ref.read(shownServiceCountProvider.notifier).value = _shownCount!;
      final shown = _shown;
      for (final target in shown.difference(_watched)) {
        _services.watch(target);
      }
      for (final target in _watched.difference(shown)) {
        _services.unwatch(target);
      }
      _watched = shown;
    });
  }

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final mobile = !density.isDesktop;
    final appLocalizations = context.appLocalizations;
    final scale = DashboardDensityScope.scaleOf(context);
    final columns = mobile ? 1 : widget.columns.clamp(1, 2);
    final rows = mobile ? ServiceStatusCard.mobileRows : ServiceStatusCard.rows;
    final shownCount = columns * rows;
    final shown = ref
        .watch(enabledServiceTargetsProvider)
        .take(shownCount)
        .toList();
    _syncShown(shown.toSet(), shownCount);
    final state = ref.watch(serviceStatusProvider);
    final services = [
      for (final target in shown)
        _ServiceView(
          target,
          state.entryOf(target),
          shownPhase(state.entryOf(target)),
        ),
    ];
    final checkedAt = services
        .map((service) => service.check?.checkedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, time) =>
              latest == null || time.isAfter(latest) ? time : latest,
        );
    final problems = services.where((service) => service.abnormal).length;
    final verdict = problems > 0
        ? DashboardChip(
            label: appLocalizations.serviceAbnormalCount(problems),
            tone: DashboardChipTone.warn,
            dot: true,
          )
        : services.isNotEmpty &&
              services.every((service) => service.check != null)
        ? DashboardChip(
            label: appLocalizations.serviceAllAvailable,
            tone: DashboardChipTone.ok,
            dot: true,
          )
        : null;
    final grid = _ServiceGrid(
      services: services,
      columns: columns,
      rows: rows,
      scale: scale,
      mobile: mobile,
    );
    return DashboardCard(
      semanticLabel: appLocalizations.serviceStatus,
      padding: mobile ? null : dashboardSummaryCardPadding(density),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: appLocalizations.serviceStatus,
            leading: [?verdict],
            trailing: [
              _CheckAllButton(
                loading: _sweeping,
                onPressed: () => _sweep(force: true),
              ),
            ],
          ),
          SizedBox(height: mobile ? 12 : 10),
          if (mobile) grid else Expanded(child: grid),
          if (!mobile) ...[
            const SizedBox(height: 8),
            _ServiceFooter(
              sweptAt: _sweptAt ?? checkedAt,
                            duration: _sweepDuration,
              interval: ServiceStatusCard.autoCheckInterval,
            ),
          ],
        ],
      ),
    );
  }
}

/// Four rows of service lines: a dot, the name, the delay's own curve, and the
/// number it ends on — the reading Loon's card gives, which a bare word per
/// tile could not.
class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({
    required this.services,
    required this.columns,
    required this.rows,
    required this.scale,
    required this.mobile,
  });

  final List<_ServiceView> services;
  final int columns;
  final int rows;
  final double scale;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final cells = <_ServiceView?>[
      for (var index = 0; index < rows * columns; index++)
        index < services.length ? services[index] : null,
    ];
    Widget rowOf(int start) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20 * scale,
      children: [
        for (final service in cells.sublist(start, start + columns))
          Expanded(
            child: service == null
                ? const SizedBox.shrink()
                : _ServiceLine(service: service, scale: scale),
          ),
      ],
    );
    return Column(
      mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
      spacing: (mobile ? 5 : 4) * scale,
      children: [
        for (var row = 0; row < rows; row++)
          if (mobile)
            SizedBox(height: 34 * scale, child: rowOf(row * columns))
          else
            Expanded(child: rowOf(row * columns)),
      ],
    );
  }
}

class _ServiceLine extends StatelessWidget {
  const _ServiceLine({required this.service, required this.scale});

  static const _nameWidth = 54.0;
  static const _valueWidth = 52.0;
  static const _dotSize = 7.0;

  final _ServiceView service;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final abnormal = service.abnormal;
    final ink = abnormal
        ? _poorInk
        : service.check == null
        ? colorScheme.onSurfaceVariant
        : _delayInk(service.check!.delay ?? 0);
    final value = service.loading ? null : service.valueOf(context);
    final style = AppTextStyle.custom(
      context,
      size: 11,
      leading: 14,
      weight: FontWeight.w600,
    ).toTabular.copyWith(color: ink);
    return Semantics(
      label: service.target.label,
      value: value ?? '',
      liveRegion: true,
      child: Tooltip(
        message: '${service.target.label}${value == null ? '' : '\n$value'}',
        excludeFromSemantics: true,
        child: Row(
          spacing: 7 * scale,
          children: [
            DecoratedBox(
              decoration: ShapeDecoration(color: ink, shape: AppShape.circle),
              child: const SizedBox.square(dimension: _dotSize),
            ),
            SizedBox(
              width: _nameWidth * scale,
              child: Text(
                service.target.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.custom(
                  context,
                  size: 11,
                  leading: 14,
                  weight: FontWeight.w500,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 16 * scale,
                child: CustomPaint(
                  painter: _SparkPainter(
                    color: ink,
                    seed: service.target.index,
                    beat: !abnormal && service.check != null,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: _valueWidth * scale,
              child: value == null
                  ? Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Container(
                        width: 26 * scale,
                        height: 7 * scale,
                        decoration: ShapeDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.16,
                          ),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    )
                  : Text(
                      value,
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line is decoration: its shape says how the service answered, never how
/// the last readings moved. A service that answers draws a heartbeat in the
/// tone of its delay and one that never answered draws a dead straight line.
/// The seed is the service's own, so no two rows beat alike.
class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.color,
    required this.seed,
    required this.beat,
  });

  static const _strokeWidth = 1.9;

  /// The beat keeps clear of the row's edges: a curve that touched them would
  /// read as clipped rather than asked to sit inside the line's height.
  static const _waveInset = 3.0;

  /// One beat, in heights relative to its own peak: a lead-in, a small dip,
  /// the spike, the drop after it, a last small rise, and back to baseline.
  static const _shape = [0.0, 0.12, -0.18, 1.0, -0.42, 0.22, 0.0];

  final Color color;
  final int seed;
  final bool beat;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final middle = size.height / 2;
    if (!beat) {
      canvas.drawLine(Offset(0, middle), Offset(size.width, middle), paint);
      return;
    }
    final path = Path();
    _addWave(path, _beats(size), size.height);
    canvas.drawPath(path, paint);
  }

  /// Every beat gets its own height and its own small baseline drift, and the
  /// seed decides how many beats fit and where they sit, so the eight rows
  /// never draw the same line twice.
  List<Offset> _beats(Size size) {
    final drift = _Drift(seed * 7919 + 17);
    final inset = min(_waveInset, size.height / 3);
    final amplitude = size.height / 2 - inset;
    final middle = size.height / 2;
    final beats = 2 + seed % 2;
    final samples = beats * _shape.length;
    final step = size.width / (samples - 1);
    final points = <Offset>[];
    for (var index = 0; index < samples; index++) {
      final height = 0.5 + drift.next() * 0.5;
      final lift = (drift.next() - 0.5) * 0.14;
      final value = (_shape[index % _shape.length] * height + lift).clamp(
        -1.0,
        1.0,
      );
      points.add(Offset(index * step, middle - value * amplitude));
    }
    return points;
  }

  /// A wave rather than a zigzag: every sample is joined to the next by a
  /// cubic whose tangents come from the neighbours either side of it.
  static void _addWave(Path path, List<Offset> points, double height) {
    path.moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final previous = points[index == 0 ? 0 : index - 1];
      final from = points[index];
      final to = points[index + 1];
      final next = points[index + 2 < points.length
          ? index + 2
          : points.length - 1];
      // Catmull-Rom tangents, clamped to the row so a wave never bulges into
      // the line above it.
      final c1 = Offset(
        from.dx + (to.dx - previous.dx) / 6,
        (from.dy + (to.dy - previous.dy) / 6).clamp(0.0, height),
      );
      final c2 = Offset(
        to.dx - (next.dx - from.dx) / 6,
        (to.dy - (next.dy - from.dy) / 6).clamp(0.0, height),
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.seed != seed ||
        oldDelegate.beat != beat;
  }
}

/// The heartbeat's own numbers: cheap, deterministic, and different per seed.
class _Drift {
  _Drift(this._state);

  int _state;

  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}

/// The card's own footnote: how often it re-checks, and when the last sweep
/// landed with how long it took.
class _ServiceFooter extends StatelessWidget {
  const _ServiceFooter({
    required this.sweptAt,
    required this.duration,
    required this.interval,
  });

  final DateTime? sweptAt;
  final Duration? duration;
  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final ink = context.colorScheme.onSurfaceVariant;
    final style = AppTextStyle.custom(
      context,
      size: 10,
      leading: 13,
      weight: FontWeight.w500,
    ).copyWith(color: ink.withValues(alpha: 0.72));
    final took = duration;
    return Row(
      spacing: 5,
      children: [
        GlyphIcon(AppGlyphs.refresh, size: 11, color: ink.withValues(alpha: 0.5)),
        Text('${interval.inSeconds}s', style: style),
        const Spacer(),
        Text(
          took == null
              ? (sweptAt == null ? '' : _clockOf(sweptAt!))
              : '${_clockOf(sweptAt ?? DateTime.now())} · '
                    '${(took.inMilliseconds / 1000).toStringAsFixed(1)}s',
          style: style,
        ),
      ],
    );
  }
}

class _CheckAllButton extends StatelessWidget {
  const _CheckAllButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final ink = colorScheme.onSurfaceVariant;
    final content = Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              // The word stays while a sweep runs: a button that becomes a
              // spinner alone loses its width and jumps under the cursor.
              if (loading)
                const SizedBox.square(
                  dimension: 12,
                  child: CommonCircleLoading(size: 12),
                )
              else
                GlyphIcon(AppGlyphs.refresh, size: 11, color: ink),
              Text(
                context.appLocalizations.serviceCheckAll,
                style: AppTextStyle.custom(
                  context,
                  size: 10.5,
                  leading: 14,
                  weight: FontWeight.w500,
                ).copyWith(color: ink),
              ),
            ],
          );
    return Semantics(
      button: true,
      label: context.appLocalizations.serviceCheckAll,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: loading ? null : onPressed,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: ShapeDecoration(
              color: ink.withValues(alpha: DashboardMaterial.whisperAlpha),
              shape: const StadiumBorder(),
            ),
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );
  }
}
