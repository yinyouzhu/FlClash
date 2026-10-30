import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

const runningVersion = '0.8.96';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;

  setUpAll(() {
    core = MockCoreHandlerInterface();
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: runningVersion,
      buildNumber: '1',
    );
  });

  setUp(() => reset(core));

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('CommonAction.updateMode', () {
    test('advances through every mode and wraps back to the first', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.values.first));

      final seen = <Mode>[container.read(patchClashConfigProvider).mode];
      for (var i = 0; i < Mode.values.length; i++) {
        action.updateMode();
        seen.add(container.read(patchClashConfigProvider).mode);
      }

      expect(seen.sublist(0, Mode.values.length), Mode.values);
      expect(seen.last, Mode.values.first, reason: 'wraps after the last mode');
    });
  });

  group('CommonAction.updateSpeedStatistics', () {
    test('toggles the tray title flag both ways', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      final initial = container.read(appSettingProvider).showTrayTitle;

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, !initial);

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, initial);
    });
  });

  group('CommonAction.updateTraffic', () {
    test('reads the whole and the proxy half, and splits them exactly', () async {
      final container = buildContainer();
      when(
        () => core.getTotalTraffic(false),
      ).thenAnswer((_) async => const Traffic(up: 300, down: 700));
      when(
        () => core.getTotalTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      final totals = container.read(trafficTotalsProvider);
      expect(totals.all, const Traffic(up: 300, down: 700));
      expect(totals.proxy, const Traffic(up: 100, down: 200));
      // The card reads all - proxy for the direct half; nothing else in the
      // tree keeps that number.
      expect(totals.all.up + totals.all.down - totals.proxy.up - totals.proxy.down, 700);
      verify(() => core.getTotalTraffic(false)).called(1);
      verify(() => core.getTotalTraffic(true)).called(1);
    });

    test('the first beat sets the baseline instead of inventing a speed', () async {
      final container = buildContainer();
      when(
        () => core.getTotalTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list, isEmpty);
      expect(container.read(totalTrafficProvider), const Traffic(up: 100, down: 200));
    });

    test('publishes the half the setting asks for', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(onlyStatisticsProxy: true));
      when(
        () => core.getTotalTraffic(false),
      ).thenAnswer((_) async => const Traffic(up: 300, down: 700));
      when(
        () => core.getTotalTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(totalTrafficProvider), const Traffic(up: 100, down: 200));
    });

    test('a failed read moves neither the totals nor the baseline', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(() => core.getTotalTraffic(any())).thenThrow(StateError('core down'));

      await expectLater(
        container.read(commonActionProvider.notifier).updateTraffic(),
        completes,
      );
      expect(container.read(totalTrafficProvider), before);
      expect(container.read(trafficTotalsProvider).all, const Traffic());
    });

    test(
      'drops concurrent in-flight updates while one is in progress',
      () async {
        final container = buildContainer();
        final completer = Completer<Traffic>();
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) => completer.future);

        final first = container
            .read(commonActionProvider.notifier)
            .updateTraffic();
        final second = container
            .read(commonActionProvider.notifier)
            .updateTraffic();

        await expectLater(second, completes);
        completer.complete(const Traffic(up: 5, down: 10));
        await first;

        verify(() => core.getTotalTraffic(any())).called(2);
        verifyNever(() => core.getTraffic(any()));
      },
    );
  });

  group('CommonAction.rateBetween', () {
    test('divides the difference by the window that actually passed', () {
      expect(
        CommonAction.rateBetween(
          const Traffic(),
          const Traffic(up: 1024, down: 2048),
          const Duration(seconds: 1),
        ),
        const Traffic(up: 1024, down: 2048),
      );
      expect(
        CommonAction.rateBetween(
          const Traffic(),
          const Traffic(up: 500, down: 1000),
          const Duration(milliseconds: 500),
        ),
        const Traffic(up: 1000, down: 2000),
      );
      expect(
        CommonAction.rateBetween(
          const Traffic(up: 100, down: 100),
          const Traffic(up: 1600, down: 2100),
          const Duration(seconds: 2),
        ),
        const Traffic(up: 750, down: 1000),
      );
    });

    test('refuses windows that say nothing about the speed', () {
      const before = Traffic(up: 10, down: 10);
      const after = Traffic(up: 20, down: 20);
      expect(
        CommonAction.rateBetween(before, after, const Duration(milliseconds: 50)),
        isNull,
        reason: 'shorter than a beat divides noise',
      );
      expect(
        CommonAction.rateBetween(before, after, const Duration(seconds: 6)),
        isNull,
        reason: 'the app was paused, not slow',
      );
    });

    test('refuses a total that went backwards', () {
      expect(
        CommonAction.rateBetween(
          const Traffic(up: 5000, down: 5000),
          const Traffic(up: 10, down: 10),
          const Duration(seconds: 1),
        ),
        isNull,
        reason: 'a restart is not a negative speed',
      );
    });
  });

  group('CommonAction.autoCheckUpdate', () {
    test('returns without a network call when the setting is off', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoCheckUpdate: false));

      await expectLater(
        container.read(commonActionProvider.notifier).autoCheckUpdate(),
        completion(isFalse),
      );
    });
  });
}
