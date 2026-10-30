import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart' show StandardMessageCodec;
import 'package:flutter/widgets.dart';

/// The frost a card gets on macOS, as a real `NSVisualEffectView` embedded
/// through a platform view.
///
/// **Disabled.** It renders, and it does give a card a genuine second vibrancy
/// layer, but on macOS a platform view is a real `NSView` composited above the
/// Flutter surface: pointer events over the card never reach the Flutter
/// widgets on it, so every button inside a card went dead. Until that is solved
/// (it is a platform-view limitation, not a hit-test tweak — returning nil from
/// `hitTest` is not enough) the dashboard keeps its Flutter-painted cards and
/// gets its glass from the window-level material instead. The native side
/// (`FrostedCardView.swift`, registered as `flclash/frosted_card`) is left in
/// place so this can be picked up again.
///
/// Flutter renders the whole app into one surface, so a normal card can only
/// be a translucent rectangle on top of the window's single global frost.
/// Loon's cards are genuine system vibrancy subviews — each one frosts what is
/// behind it, so the panel reads as glass rather than as tinted alpha. This
/// widget is how the dashboard gets the same thing on macOS.
///
/// All of the look is passed through creation params, so tuning it is a Dart
/// change plus a hot restart, never a native rebuild.
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.radius,
    this.material = _material,
    this.appearance = _appearance,
    this.blending = _blending,
    this.tint = _tint,
  });

  /// Panel shape.
  final double radius;

  /// `NSVisualEffectView.material` — see `FrostedCardView.material` for the
  /// accepted names. `sidebar` is the system's translucent panel material,
  /// the closest match to a card sitting on a frosted window.
  final String material;

  /// Forced appearance, so the card frosts dark even when the window is not
  /// key. `aqua` on a dark theme washes the panel out; `darkAqua` keeps it.
  final String appearance;

  /// `.withinWindow` frosts the window's own backdrop (the global frost), which
  /// keeps the card's colour stable and coherent instead of re-sampling the
  /// raw desktop the way `.behindWindow` would.
  final String blending;

  /// Optional colour layered over the material. `NSVisualEffectView` swallows
  /// a tint painted on its own layer, so the native side applies this on a
  /// separate sibling view. Null leaves the material's own colour.
  final Color? tint;

  static const _material = 'underWindowBackground';
  static const _appearance = 'darkAqua';
  static const _blending = 'withinWindow';
  /// Loon's cards measure ~0.71x the brightness of its pane, i.e. a translucent
  /// darkening rather than an opaque panel. The material alone already lands at
  /// ~0.72, so this only nudges it down enough for the card edge to read.
  static const Color _tint = Color(0x12000000);

  /// Platform views only exist on macOS here; elsewhere the card falls back to
  /// its plain Flutter tint.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) {
      return const SizedBox.shrink();
    }
    return AppKitView(
      viewType: 'flclash/frosted_card',
      // The frost is a background: the card's own InkWell sits above it and
      // must keep getting the pointer.
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      creationParams: <String, Object?>{
        'radius': radius,
        'material': material,
        'appearance': appearance,
        'blending': blending,
        'tint': tint?.toARGB32(),
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
