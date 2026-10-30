import 'package:fl_clash/common/app_identity.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// One process as the dashboard sums it up: the traffic it has moved this run,
/// the connections it holds open right now, and the executable behind it.
class ProcessUsage {
  const ProcessUsage({
    required this.name,
    required this.executable,
    required this.traffic,
    required this.connections,
    required this.speed,
  });

  final String name;
  final String executable;
  final int traffic;
  final int connections;
  final int speed;
}

/// The processes this run has carried, in the shape Loon's own card reads them:
/// a title row that doubles as the column headers, then one app per line with
/// its icon, its name, and the three numbers.
class ProcessListCard extends StatelessWidget {
  const ProcessListCard({super.key, required this.processes});

  static const _maxRows = 4;

  /// Loon's own rows are a fixed 44 high, so a short list leaves the card's
  /// spare space at the bottom instead of stretching two rows across it.
  static const _rowHeight = 44.0;
  static const _headerGap = 4.0;

  final List<ProcessUsage> processes;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final rows = processes.take(_maxRows).toList();
    final scale = DashboardDensityScope.scaleOf(context);
    return DashboardCard(
      semanticLabel: appLocalizations.activeProcesses,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Loon's rows are 44 high, but a card this short cannot spend that
          // on four of them; the row gives way rather than overflowing.
          final room =
              constraints.maxHeight - _Header.height - _headerGap;
          final rowHeight = rows.isEmpty
              ? 0.0
              : math.min(_rowHeight * scale, room / rows.length);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: appLocalizations.activeProcesses,
                labels: [
                  appLocalizations.speed,
                  appLocalizations.connections,
                  appLocalizations.traffic,
                ],
              ),
              const SizedBox(height: _headerGap),
              if (rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          appLocalizations.noData,
                          style: DashboardText.label(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          appLocalizations.activeProcessesHint,
                          style: DashboardText.legendLabel(context),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              for (final usage in rows)
                SizedBox(
                  height: rowHeight,
                  child: _ProcessRow(usage: usage),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The title line doubles as the column headers, and shares the rows' own
/// widths so every label sits over its numbers. The card's stock header caps
/// its trailing side and scales it down, which would break that alignment.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.labels});

  static const height = 24.0;

  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      height: height,
      child: Row(
        spacing: _ProcessRow.gap,
        children: [
          GlyphIcon(
            AppGlyphs.appsList,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.cardTitle(context),
            ),
          ),
          _Column(label: labels[0], width: _ProcessRow.speedWidth),
          _Column(label: labels[1], width: _ProcessRow.countWidth),
          _Column(label: labels[2], width: _ProcessRow.trafficWidth),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      // A Text shrink-wraps to its own glyphs, so textAlign alone leaves it
      // against the column's left edge. Centering the whole cell keeps every
      // value stacked under its header, the way Loon lines the columns up.
      child: Align(
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
      ),
    );
  }
}

class _ProcessRow extends StatefulWidget {
  const _ProcessRow({required this.usage});

  static const avatarSize = 22.0;
  static const speedWidth = 72.0;
  static const countWidth = 46.0;
  static const trafficWidth = 76.0;
  static const gap = 6.0;

  final ProcessUsage usage;

  @override
  State<_ProcessRow> createState() => _ProcessRowState();
}

class _ProcessRowState extends State<_ProcessRow> {
  Future<AppIdentity?>? _identity;

  @override
  void initState() {
    super.initState();
    _identity = AppIdentities.of(widget.usage.executable);
  }

  @override
  void didUpdateWidget(covariant _ProcessRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usage.executable != widget.usage.executable) {
      _identity = AppIdentities.of(widget.usage.executable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = widget.usage;
    return FutureBuilder<AppIdentity?>(
      future: _identity,
      builder: (context, snapshot) {
        final identity = snapshot.data;
        return Row(
          spacing: _ProcessRow.gap,
          children: [
            _AppIcon(icon: identity?.icon, letter: _letterOf(identity, usage)),
            Expanded(
              child: Text(
                _nameOf(identity, usage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.processName(context),
              ),
            ),
            _Column(
              label: '${dashboardTraffic(usage.speed)}/s',
              width: _ProcessRow.speedWidth,
            ),
            _Column(label: '${usage.connections}', width: _ProcessRow.countWidth),
            _Column(
              label: dashboardTraffic(usage.traffic),
              width: _ProcessRow.trafficWidth,
            ),
          ],
        );
      },
    );
  }

  /// The Finder's name for the app the executable belongs to, and the process
  /// name itself for a binary that has no bundle.
  String _nameOf(AppIdentity? identity, ProcessUsage usage) {
    final app = identity?.name?.trim() ?? '';
    if (app.isNotEmpty) {
      return app;
    }
    final process = usage.name;
    if (process.isEmpty) {
      return '?';
    }
    // A system XPC reports a reverse-domain identifier and no bundle; its
    // last segment ("Networking") reads better than the whole string, and the
    // first one is always the vendor.
    if (process.contains('.') && !process.contains(' ')) {
      final tail = process.split('.').last;
      if (tail.isNotEmpty) {
        return tail;
      }
    }
    return process;
  }

  String _letterOf(AppIdentity? identity, ProcessUsage usage) {
    final name = _nameOf(identity, usage);
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }
}

/// The app's own icon when the system can hand it over, and a lettered tile
/// for the binaries that have none (curl, python3, a stray helper).
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon, required this.letter});

  final Uint8List? icon;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final colorScheme = context.colorScheme;
    final icon = this.icon;
    return Container(
      width: _ProcessRow.avatarSize,
      height: _ProcessRow.avatarSize,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: colors.tone,
        shape: AppShape.all(AppCorner.sm),
      ),
      child: icon == null
          ? Text(
              letter,
              maxLines: 1,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            )
          : Image.memory(
              icon,
              width: _ProcessRow.avatarSize,
              height: _ProcessRow.avatarSize,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
