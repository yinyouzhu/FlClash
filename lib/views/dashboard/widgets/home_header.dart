import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/typography.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// The one row across the top of the home grid: the page's own title, the
/// profile in use, and the outbound mode, where the rest of the page reads as
/// its content. It is the page's bar, so it spans the window while the grid
/// under it keeps to [_maxWidth].
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static const _maxWidth = 1440.0;

  /// Loon's bar switch, measured off its title bar at 2x: a 684 px track 66 px
  /// tall, so 330 by 32 pt, with its three segments 110 pt apiece. Ours carries
  /// two-character labels, so the same segment width leaves the same shape
  /// rather than the same total once the glyph is counted in.
  static const _maxModeWidth = 330.0;

  /// How tall the page's bar stands, a little over the row it holds so the
  /// bar clears the title it sets.
  static const barHeight = 52.0;

  /// The row itself, and the mode's own pill inside it.
  static const _height = 40.0;
  static const _modeHeight = 32.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final height = _height * scale;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The switch keeps Loon's width, but never at the cost of the
              // profile it sits beside: a narrow bar or a scaled-up text size
              // hands it whatever room is left instead of overflowing.
              final modeWidth = math.min(
                _maxModeWidth * scale,
                math.max(0.0, constraints.maxWidth - 96 * scale),
              );
              return Row(
                spacing: 12,
                children: [
                  // Loon's title measures 21 pt of ink in its bar; the page
                  // title's own 24 is a step heavier than the bar it sits in.
                  // Left unscaled: the text scaler already reaches this style.
                  Text(
                    appLocalizations.dashboard,
                    maxLines: 1,
                    style: AppTextStyle.custom(
                      context,
                      size: 22,
                      leading: 28,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      profile?.realLabel ?? appLocalizations.profiles,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context),
                    ),
                  ),
                  SizedBox(
                    width: modeWidth,
                    height: _modeHeight * scale,
                    child: DashboardSegmented<Mode>(
                      items: Mode.values,
                      value: mode,
                      height: _modeHeight * scale,
                      labelOf: (item) => item.label,
                      glyphOf: _glyphOf,
                      onSelected: (item) => _changeMode(ref, item),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The glyph each mode shows while it is the chosen one; Loon draws a glyph
  /// on the selected segment only, so this never widens the other two.
  static Glyph _glyphOf(Mode mode) => switch (mode) {
    Mode.rule => AppGlyphs.split,
    Mode.global => AppGlyphs.vpn,
    Mode.direct => AppGlyphs.link,
  };

  void _changeMode(WidgetRef ref, Mode mode) {
    if (ref.read(patchClashConfigProvider).mode == mode) return;
    ref.read(setupActionProvider.notifier).changeMode(mode);
  }
}
