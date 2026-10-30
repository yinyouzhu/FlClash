part of '../state.dart';

typedef DynamicColorSeeds = ({
  Color? lightSeed,
  Color? darkSeed,
  Color accentColor,
});

extension DynamicColorSeedsExt on DynamicColorSeeds {
  Color seedOf(Brightness brightness) =>
      switch (brightness) {
        Brightness.light => lightSeed,
        Brightness.dark => darkSeed,
      } ??
      accentColor;
}

@Riverpod(keepAlive: true)
class DynamicColor extends _$DynamicColor {
  @override
  DynamicColorSeeds build() {
    return (
      lightSeed: null,
      darkSeed: null,
      accentColor: const Color(defaultPrimaryColor),
    );
  }

  void seed({Color? lightSeed, Color? darkSeed, required Color accentColor}) {
    state = (
      lightSeed: lightSeed,
      darkSeed: darkSeed,
      accentColor: accentColor,
    );
  }
}

@riverpod
ColorScheme genColorScheme(
  Ref ref,
  Brightness brightness, {
  Color? color,
  bool ignoreConfig = false,
  bool? pureBlack,
}) {
  final themeSetting = ref.watch(
    themeSettingProvider.select(
      (state) => (
        primaryColor: state.primaryColor,
        colorStyle: state.colorStyle,
        pureBlack: state.pureBlack,
      ),
    ),
  );
  final dynamicColor = ref.watch(dynamicColorProvider);
  final Color seedColor;
  if (color == null &&
      (ignoreConfig == true || themeSetting.primaryColor == null)) {
    seedColor = dynamicColor.seedOf(brightness);
  } else {
    seedColor = color ?? Color(themeSetting.primaryColor!);
  }
  return _cachedColorScheme(
    seedColor,
    brightness,
    themeSetting.colorStyle,
    pureBlack ?? themeSetting.pureBlack,
  );
}

const _maxCachedColorSchemes = 64;

final _colorSchemes = <(Color, Brightness, ColorStyle, bool), ColorScheme>{};

ColorScheme _cachedColorScheme(
  Color seedColor,
  Brightness brightness,
  ColorStyle style,
  bool pureBlack,
) {
  final key = (seedColor, brightness, style, pureBlack);
  final colorScheme =
      _colorSchemes.remove(key) ??
      seededColorScheme(
        seedColor: seedColor,
        brightness: brightness,
        style: style,
      ).toLoonSurfaces().toPureBlack(pureBlack);
  _colorSchemes[key] = colorScheme;
  if (_colorSchemes.length > _maxCachedColorSchemes) {
    _colorSchemes.remove(_colorSchemes.keys.first);
  }
  return colorScheme;
}

/// Whether the window is a frosted pane rather than a solid one.
///
/// On macOS it always is. The vibrancy material under Loon's black tint *is*
/// the look this app is chasing, and leaving it to a stored preference meant any
/// install whose config predates the flag — the generated decoder defaulted the
/// missing key to `false` — came up as opaque charcoal, reading to the user as
/// "the frost disappeared again" with no switch visibly off anywhere. A toggle
/// that can silently flatten the whole window has no value on this platform, so
/// macOS ignores it; Windows and Linux keep it, where the material is optional.
@riverpod
bool glassPane(Ref ref) {
  if (system.isMacOS) {
    return true;
  }
  return ref.watch(themeSettingProvider.select((state) => state.sidebarBlur));
}

typedef WindowBlurRequest = ({bool enabled, Brightness brightness, Color tint});

@riverpod
WindowBlurRequest windowBlurRequest(Ref ref) {
  final enabled = ref.watch(glassPaneProvider);
  final brightness = ref.watch(currentBrightnessProvider);
  final colorScheme = ref.watch(genColorSchemeProvider(brightness));
  return (
    enabled: enabled,
    brightness: brightness,
    tint: colorScheme.surfaceContainer,
  );
}

@riverpod
Brightness currentBrightness(Ref ref) {
  final themeMode = ref.watch(
    themeSettingProvider.select((state) => state.themeMode),
  );
  final systemBrightness = ref.watch(systemBrightnessProvider);
  return switch (themeMode) {
    ThemeMode.system => systemBrightness,
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
  };
}
