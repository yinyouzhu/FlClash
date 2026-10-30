import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'stat_bar.dart';

/// Everything the connections this page has watched moved, split by the route
/// it took out of the machine.
///
/// Same skeleton as [ConnectionSplitCard] and for the same reason: Loon's two
/// summary cards read as a pair, so their titles, figures, bars and legends
/// all sit on the same lines.
class TrafficSummaryCard extends StatelessWidget {
  const TrafficSummaryCard({
    super.key,
    required this.direct,
    required this.proxy,
  });

  final int direct;
  final int proxy;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = DashboardColors.of(context);
    final show = (direct + proxy).traffic;
    return DashboardCard(
      semanticLabel: appLocalizations.trafficUsage,
      padding: dashboardSummaryCardPadding(DashboardDensityScope.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(title: appLocalizations.trafficUsage),
          const SizedBox(height: 6),
          // The unit trails the figure on the same baseline — Loon sets ``MB``
          // at about a third of the number's height, not as a second label.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: show.value,
                  style: DashboardText.metric(context),
                ),
                TextSpan(
                  text: ' ${show.unit}',
                  style: DashboardText.metricUnit(context),
                ),
              ],
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          DashboardStatBar(
            segments: [(direct, colors.direct), (proxy, colors.proxyMark)],
          ),
          const SizedBox(height: 11),
          Row(
            spacing: legendSpacing(context),
            children: [
              Expanded(
                child: DashboardLegendItem(
                  color: colors.direct,
                  label: appLocalizations.direct,
                  value: dashboardTraffic(direct),
                ),
              ),
              Expanded(
                child: DashboardLegendItem(
                  color: colors.proxyMark,
                  label: appLocalizations.proxy,
                  value: dashboardTraffic(proxy),
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
