import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window/window.dart';

class Window implements WindowPort {
  /// A tint this heavy keeps the page's own charcoal in charge while the
  /// material still shimmers through; lower values washed the card step out
  /// over a light desktop.
  static const _tintOpacity = 0.75;
  /// How much of its own colour the page keeps over the native frost. It is
  /// handed to the theme as the page's alpha.
  ///
  /// Zero, because Loon has no such layer: its window is the vibrancy material
  /// plus one black tint, nothing else. This layer paints the theme's neutral
  /// cool grey, so any value above zero desaturates the warmth coming through
  /// from the desktop — the "wrong colour, nothing like Loon" the user reported.
  static const _macTintOpacity = 0.0;
  /// The frost's colour on macOS. Loon paints a black tint over the vibrancy
  /// material, so the pane's hue is entirely the desktop's and the tint only
  /// decides how dark it is. Measured off Loon's own view: aqua 0.18, dark 0.24.
  static const _macTintAquaAlpha = 0.18;
  static const _macTintDarkAlpha = 0.24;
  /// Thins the vibrancy material itself. **Must stay 1.0.** Masking the
  /// material below 1 does not produce "lighter glass": the masked-out part is
  /// simply not drawn, so the *unblurred* desktop shows straight through and any
  /// window behind becomes legible — the pane reads as a hole, not as glass.
  static const _macFrostOpacity = 1.0;
  static Window? _instance;
  bool _supportsPosition = false;
  WindowEffect? _blurEffect;
  late final WindowVisibilityController _visibility =
      WindowVisibilityController(
        showWindow: _showWindow,
        hideWindow: _hideWindow,
        isWindowVisible: _isWindowVisible,
        setSkipTaskbar: (skip) => desktopWindow.setSkipTaskbar(skip),
        dockSettleDuration: system.isMacOS
            ? const Duration(seconds: 1)
            : Duration.zero,
      );

  Window._internal();

  factory Window() {
    _instance ??= Window._internal();
    return _instance!;
  }

  Future<void> init(int version, WindowProps props) async {
    if (!safeModeBuild) {
      if (system.isWindows) {
        for (final scheme in protocolSchemes) {
          protocol.register(scheme);
        }
      }
      if (system.isLinux) {
        unawaited(protocol.registerLinux(protocolSchemes));
      }
    }
    await desktopWindow.ensureInitialized();
    _supportsPosition = !system.isMacOS;
    if (system.isLinux) {
      _supportsPosition = await desktopWindow.isPositionSupported();
    }
    if (!system.isMacOS || version > 10) {
      await desktopWindow.setTitleBarStyle(TitleBarStyle.hidden);
    }
    await desktopWindow.setSize(props.savedSize ?? await _defaultSize());
    await desktopWindow.setMinimumSize(const Size(380, 400));
    await _windowPosition(props);
    await desktopWindow.setPreventClose(true);
  }

  Future<Size> _defaultSize() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      return fittedWindowSize(display.visibleSize ?? display.size);
    } catch (_) {
      return defaultWindowSize;
    }
  }

  Future<void> _windowPosition(WindowProps props) async {
    if (!_supportsPosition) {
      return;
    }
    final position = props.left == null || props.top == null
        ? null
        : restoredWindowPosition(
            props,
            displays: await screenRetriever.getAllDisplays(),
            currentScale: system.isWindows ? _windowScale : null,
          );
    if (position == null) {
      await desktopWindow.setAlignment(Alignment.center);
    } else {
      await desktopWindow.setPosition(position);
    }
  }

  double get _windowScale =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;

  @override
  Future<WindowProps?> captureNormalGeometry(WindowProps current) async {
    final states = await Future.wait<bool>([
      desktopWindow.isMaximized(),
      desktopWindow.isFullScreen(),
      desktopWindow.isMinimized(),
    ]);
    if (states.any((state) => state)) {
      return null;
    }

    final bounds = await desktopWindow.getBounds();
    if (!bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }
    final hasValidPosition =
        bounds.left.isFinite && bounds.top.isFinite && _supportsPosition;
    return current.copyWith(
      width: bounds.width,
      height: bounds.height,
      left: hasValidPosition ? bounds.left : current.left,
      top: hasValidPosition ? bounds.top : current.top,
      scale: hasValidPosition && system.isWindows
          ? _windowScale
          : current.scale,
    );
  }

  /// A probe that finds no effect is not cached, so a failure at startup
  /// does not pin the toggle to off for the rest of the session.
  Future<WindowEffect> _resolveBlurEffect() async {
    final cached = _blurEffect;
    if (cached != null) {
      return cached;
    }
    // macOS 26's Liquid Glass (`.glass`) is a clear, refractive material whose
    // centre shows the wallpaper straight through instead of frosting it, so it
    // never reads as the uniform frosted panel Loon uses. The classic vibrancy
    // material (`.blur`) frosts the desktop behind the whole window, which is
    // the look we want; keep `.glass` only as a last-resort fallback.
    final candidates = system.isMacOS
        ? const [WindowEffect.blur, WindowEffect.glass]
        : const [WindowEffect.mica, WindowEffect.acrylic, WindowEffect.blur];
    for (final effect in candidates) {
      if (await desktopWindow.isEffectSupported(effect)) {
        return _blurEffect = effect;
      }
    }
    return WindowEffect.none;
  }

  /// Only Windows 10's accent blur takes the tint natively; it draws nothing
  /// without one. Every material still keeps the sidebar's own color half over
  /// it, or the rail takes the hue of whatever lies behind the window while
  /// the content beside it keeps the theme's.
  @override
  Future<double?> setBlur({
    required bool enabled,
    required Brightness brightness,
    required Color tint,
  }) async {
    if (system.isLinux) {
      return null;
    }
    final effect = enabled ? await _resolveBlurEffect() : WindowEffect.none;
    await desktopWindow.setEffect(
      effect,
      // Windows takes its native accent tint. On macOS the tint is plain black
      // over the vibrancy material, exactly as Loon does it, so the pane keeps
      // the desktop's own hue and only gains weight — a coloured tint here would
      // double-tint what is already coming through the frost.
      tint: !enabled
          ? null
          : system.isWindows
          ? tint.withValues(alpha: _tintOpacity)
          : Colors.black.withValues(
              alpha: brightness == Brightness.dark
                  ? _macTintDarkAlpha
                  : _macTintAquaAlpha,
            ),
      brightness: brightness,
      opacity: system.isMacOS && enabled ? _macFrostOpacity : null,
    );
    return effect == WindowEffect.none ? null : _macTintOpacity;
  }

  /// Every desktop runner leaves the window hidden until [init] reveals it, so
  /// a failure before that point would leave the error screen with no window.
  Future<void> showInitFailure({required AsyncCallback onExit}) async {
    desktopWindow.addListener(_InitFailureWindowListener(onExit));
    try {
      await desktopWindow.ensureInitialized();
      await desktopWindow.setPreventClose(true);
      await desktopWindow.setTitleBarStyle(TitleBarStyle.normal);
      if (await desktopWindow.isVisible()) {
        return;
      }
      await desktopWindow.setSize(const Size(680, 580));
      await desktopWindow.center();
      await desktopWindow.show();
      await desktopWindow.focus();
    } catch (e) {
      commonPrint.log(
        'show init failure window failed ${e.toString()}',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  Future<void> show() => _visibility.show();

  @override
  Future<void> hide() => _visibility.hide();

  @override
  Future<void> toggle() => _visibility.toggle();

  Future<void> _showWindow() async {
    await desktopWindow.show();
    await desktopWindow.focus();
  }

  Future<void> _hideWindow() async {
    await desktopWindow.hide();
  }

  Future<bool> _isWindowVisible() async {
    return desktopWindow.isVisible();
  }

  @override
  Future<void> close() async {
    await desktopWindow.close();
  }

  @override
  void forceExit() {
    exit(0);
  }
}

/// Keeps a margin of the work area around a first window on a small screen.
@visibleForTesting
Size fittedWindowSize(Size visible) => Size(
  math.min(defaultWindowSize.width, visible.width * 0.9),
  math.min(defaultWindowSize.height, visible.height * 0.9),
);

/// On Windows the plugin scales by the window's monitor and screen_retriever by
/// each display's own, so only physical pixels compare across mixed scales.
@visibleForTesting
Offset? restoredWindowPosition(
  WindowProps props, {
  required List<Display> displays,
  double? currentScale,
}) {
  final savedScale = currentScale == null ? 1.0 : props.scale ?? currentScale;
  final topLeft = Offset(props.left!, props.top!) * savedScale;
  final bottomRight =
      topLeft + props.size.bottomRight(Offset.zero) * savedScale;
  final isVisible = displays.any((display) {
    final position = display.visiblePosition;
    if (position == null) {
      return false;
    }
    final scale = currentScale == null
        ? 1.0
        : display.scaleFactor?.toDouble() ?? 1.0;
    final bounds = position & display.size;
    final physical = Rect.fromLTRB(
      bounds.left * scale,
      bounds.top * scale,
      bounds.right * scale,
      bounds.bottom * scale,
    );
    return physical.contains(topLeft) || physical.contains(bottomRight);
  });
  return isVisible ? topLeft / (currentScale ?? 1.0) : null;
}

class _InitFailureWindowListener with WindowListener {
  final AsyncCallback onExit;

  _InitFailureWindowListener(this.onExit);

  @override
  void onWindowClose() => unawaited(onExit());

  @override
  void onWindowShouldTerminate() => unawaited(onExit());
}

/// Serializes visibility requests so a burst of hotkey toggles lands in
/// order, and holds back the Dock-hiding activation policy switch while a
/// preceding regular switch settles: flipping regular → accessory → regular
/// within about a second leaves macOS with stray Dock icons.
class WindowVisibilityController {
  WindowVisibilityController({
    required Future<void> Function() showWindow,
    required Future<void> Function() hideWindow,
    required Future<bool> Function() isWindowVisible,
    required Future<void> Function(bool skip) setSkipTaskbar,
    required this.dockSettleDuration,
  }) : _showWindow = showWindow,
       _hideWindow = hideWindow,
       _isWindowVisible = isWindowVisible,
       _setSkipTaskbar = setSkipTaskbar;

  final Future<void> Function() _showWindow;
  final Future<void> Function() _hideWindow;
  final Future<bool> Function() _isWindowVisible;
  final Future<void> Function(bool skip) _setSkipTaskbar;
  final Duration dockSettleDuration;

  Future<void>? _queue;
  Timer? _dockSettleTimer;
  bool _dockHidePending = false;

  Future<void> show() => _enqueue(_show);

  Future<void> hide() => _enqueue(_hide);

  Future<void> toggle() => _enqueue(() async {
    if (await _isWindowVisible()) {
      await _hide();
    } else {
      await _show();
    }
  });

  Future<void> _enqueue(Future<void> Function() step) {
    final previous = _queue;
    final result = previous == null ? step() : previous.then((_) => step());
    final tail = result.catchError((_) {});
    _queue = tail;
    tail.whenComplete(() {
      if (identical(_queue, tail)) {
        _queue = null;
      }
    });
    return result;
  }

  Future<void> _show() async {
    _dockHidePending = false;
    await _showWindow();
    await _setSkipTaskbar(false);
    _dockSettleTimer?.cancel();
    _dockSettleTimer = dockSettleDuration == Duration.zero
        ? null
        : Timer(dockSettleDuration, _onDockSettled);
  }

  Future<void> _hide() async {
    await _hideWindow();
    if (_dockSettleTimer?.isActive ?? false) {
      _dockHidePending = true;
      return;
    }
    await _setSkipTaskbar(true);
  }

  void _onDockSettled() {
    _dockSettleTimer = null;
    if (!_dockHidePending) {
      return;
    }
    unawaited(
      _enqueue(() async {
        if (!_dockHidePending) {
          return;
        }
        _dockHidePending = false;
        await _setSkipTaskbar(true);
      }),
    );
  }
}

final window = system.isDesktop ? Window() : null;
