import 'package:fl_clash/ui/color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dark = seededColorScheme(
    seedColor: const Color(0xFF007AFF),
    brightness: Brightness.dark,
  );
  final light = seededColorScheme(
    seedColor: const Color(0xFF007AFF),
    brightness: Brightness.light,
  );

  group('toLoonSurfaces', () {
    test('dark takes the Loon charcoal whatever the seed', () {
      final scheme = dark.toLoonSurfaces();
      expect(scheme.surface, const Color(0xFF242222));
      expect(scheme.surfaceContainer, const Color(0xFF282828));
      // The chrome stays neutral charcoal: no seed hue in it.
      expect(scheme.surfaceContainer.r, scheme.surfaceContainer.b);
      expect(scheme.primary, dark.primary);
      expect(scheme.onSurface, dark.onSurface);
    });

    test('keeps the floors apart enough for an elevated sheet to layer', () {
      final scheme = dark.toLoonSurfaces();
      expect(
        scheme.surfaceContainer.computeLuminance(),
        greaterThan(scheme.surface.computeLuminance()),
      );
      expect(
        scheme.surfaceContainerHigh.computeLuminance(),
        greaterThan(scheme.surfaceContainer.computeLuminance()),
      );
      expect(
        scheme.surfaceContainerHighest.computeLuminance(),
        greaterThan(scheme.surfaceContainerHigh.computeLuminance()),
      );
    });

    test('leaves light alone', () {
      expect(light.toLoonSurfaces(), light);
    });

    test('pure black still bottoms out over it', () {
      final scheme = dark.toLoonSurfaces().toPureBlack(true);
      expect(scheme.surface, Colors.black);
      expect(
        scheme.surfaceContainer.computeLuminance(),
        lessThan(dark.toLoonSurfaces().surfaceContainer.computeLuminance()),
      );
    });
  });

  group('withGlassPage', () {
    test('dark leaves the alpha on the page role, surface', () {
      final base = dark.toLoonSurfaces();
      final glass = base.withGlassPage(0.5);
      expect(glass.surface.a, closeTo(0.5, 0.01));
      expect(glass.surfaceContainer, base.surfaceContainer);
    });

    test('light leaves the alpha on the page role, surfaceContainer', () {
      final glass = light.withGlassPage(0.5);
      expect(glass.surfaceContainer.a, closeTo(0.5, 0.01));
      expect(glass.surface, light.surface);
    });
  });
}
