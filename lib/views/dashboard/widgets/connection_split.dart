import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'stat_bar.dart';

/// The connections this run has opened, split by where they go: straight out,
/// through the selected node, or into the reject rule.
///
/// The numbers are counted as each connection opens, so they only grow; only a
/// stop clears them. Reading them off the list of connections still open made
/// the card fall back whenever traffic went quiet, which read as lost history.
///
/// Laid out the way Loon's own card is measured: title, the count, the bar,
/// then a legend whose numbers sit under their labels. The vertical rhythm is
/// fixed rather than spaced, because Loon keeps its content against the top of
/// the card and lets the slack fall at the bottom.
class ConnectionSplitCard extends StatelessWidget {
  const ConnectionSplitCard({
    super.key,
    required this.direct,
    required this.proxy,
    required this.reject,
  });

  final int direct;
  final int proxy;
  final int reject;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = DashboardColors.of(context);
    final total = direct + proxy + reject;
    final items = [
      (colors.direct, appLocalizations.direct, direct),
      (colors.proxyMark, appLocalizations.proxy, proxy),
      (colors.rejectMark, appLocalizations.reject, reject),
    ];
    return DashboardCard(
      semanticLabel: appLocalizations.sessionConnections,
      padding: dashboardSummaryCardPadding(DashboardDensityScope.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loon's card carries no glyph beside its title.
          DashboardCardHeader(title: appLocalizations.sessionConnections),
          const SizedBox(height: 6),
          Text('$total', maxLines: 1, style: DashboardText.metric(context)),
          const SizedBox(height: 2),
          DashboardStatBar(
            segments: [for (final (color, _, value) in items) (value, color)],
          ),
          const SizedBox(height: 11),
          Row(
            spacing: legendSpacing(context),
            children: [
              for (final (color, label, value) in items)
                Expanded(
                  child: DashboardLegendItem(
                    color: color,
                    label: label,
                    value: '$value',
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
