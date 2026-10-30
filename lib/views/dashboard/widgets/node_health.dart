import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// The selected node, how it answers, and the group it came from. The delay
/// takes the card's centre the way a watch face does; the identities sit small
/// above and below it.
class NodeHealthCard extends ConsumerWidget {
  const NodeHealthCard({super.key});

  static const _okDelay = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final groups = ref.watch(visibleGroupsStateProvider).value;
    final group = groups.isEmpty ? null : groups.first;
    final groupName = group?.name ?? '';
    final delay = ref.watch(delayProvider(proxyName: groupName));
    final running = ref.watch(isStartProvider);
    final suspended = running && ref.watch(suspendProvider);
    final alive = delay != null && delay > 0;
    final toneColor = !alive
        ? colorScheme.onSurfaceVariant
        : delay > _okDelay
        ? DashboardColors.of(context).warn
        : DashboardColors.of(context).ok;
    final status = suspended
        ? appLocalizations.suspended
        : running
        ? appLocalizations.running
        : appLocalizations.notRunning;
    return DashboardCard(
      semanticLabel: appLocalizations.nodeHealth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.status,
            title: appLocalizations.nodeHealth,
            trailing: [
              DashboardChip(
                label: status,
                tone: running ? DashboardChipTone.ok : DashboardChipTone.idle,
                dot: true,
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 6,
            children: [
              Text(
                alive ? '$delay' : '--',
                maxLines: 1,
                style: DashboardText.figure(
                  context,
                  AppTextStyle.display,
                  color: alive ? toneColor : colorScheme.onSurfaceVariant,
                ),
              ),
              Text('ms', style: DashboardText.unit(context)),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 16,
            children: [
              Expanded(
                child: _SubStat(
                  label: appLocalizations.proxyGroup,
                  value: groupName,
                ),
              ),
              Expanded(
                child: _SubStat(
                  label: appLocalizations.nodes,
                  value: '${group?.all.length ?? 0}',
                ),
              ),
              _ActionPill(
                label: running ? appLocalizations.stop : appLocalizations.start,
                onPressed: () =>
                    ref.read(commonActionProvider.notifier).toggleRunning(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  const _SubStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        Text(
          value.isEmpty ? '--' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.rowTitle(context),
        ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    const shape = AppShape.full;
    return Semantics(
      button: true,
      label: label,
      child: FocusRing(
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onPressed,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: colorScheme.primary,
              shape: shape,
            ),
            child: Text(
              label,
              maxLines: 1,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
