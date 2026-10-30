import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// One process as the dashboard sums it up from its live connections.
class ProcessUsage {
  const ProcessUsage({
    required this.name,
    required this.traffic,
    required this.connections,
    required this.speed,
  });

  final String name;
  final int traffic;
  final int connections;
  final int speed;
}

/// The processes holding the most connections, taken from the connection
/// list rather than sampled separately.
class ProcessListCard extends StatelessWidget {
  const ProcessListCard({super.key, required this.processes});

  static const _maxRows = 5;

  final List<ProcessUsage> processes;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final rows = processes.take(_maxRows).toList();
    return DashboardCard(
      semanticLabel: appLocalizations.activeProcesses,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.appsList,
            title: appLocalizations.activeProcesses,
            trailing: [
              Text('${processes.length}', style: DashboardText.label(context)),
            ],
          ),
          const SizedBox(height: 8),
          _ColumnHeader(),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  appLocalizations.noData,
                  style: DashboardText.label(context),
                ),
              ),
            ),
          for (final usage in rows) Expanded(child: _ProcessRow(usage: usage)),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = DashboardText.label(context);
    final appLocalizations = context.appLocalizations;
    return Row(
      spacing: 10,
      children: [
        const SizedBox(width: _ProcessRow.avatarSize),
        Expanded(
          child: Text(
            appLocalizations.process,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        SizedBox(
          width: _ProcessRow.speedWidth,
          child: Text(
            appLocalizations.speed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
        SizedBox(
          width: _ProcessRow.countWidth,
          child: Text(
            appLocalizations.connections,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
        SizedBox(
          width: _ProcessRow.trafficWidth,
          child: Text(
            appLocalizations.traffic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.usage});

  static const avatarSize = 28.0;
  static const speedWidth = 88.0;
  static const countWidth = 76.0;
  static const trafficWidth = 88.0;

  final ProcessUsage usage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final name = usage.name.isEmpty ? '?' : usage.name;
    return Row(
      spacing: 10,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: colors.tone,
            shape: AppShape.all(AppCorner.sm),
          ),
          child: Text(
            name.substring(0, 1).toUpperCase(),
            maxLines: 1,
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context),
          ),
        ),
        SizedBox(
          width: speedWidth,
          child: Text(
            '${dashboardTraffic(usage.speed)}/s',
            maxLines: 1,
            textAlign: TextAlign.end,
            style: DashboardText.label(context),
          ),
        ),
        SizedBox(
          width: countWidth,
          child: Text(
            '${usage.connections}',
            maxLines: 1,
            textAlign: TextAlign.end,
            style: DashboardText.label(context),
          ),
        ),
        SizedBox(
          width: trafficWidth,
          child: Text(
            dashboardTraffic(usage.traffic),
            maxLines: 1,
            textAlign: TextAlign.end,
            style: DashboardText.label(context),
          ),
        ),
      ],
    );
  }
}
