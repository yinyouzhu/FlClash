part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  /// A rate is only believed over a window this long to this long: shorter
  /// than a beat the division is noise, longer and the app was paused rather
  /// than slow, so the sample is dropped and the window restarts.
  static const _minRateWindow = Duration(milliseconds: 200);
  static const _maxRateWindow = Duration(seconds: 3);

  /// The totals read last, and when they were read, so the speed can be the
  /// difference divided by the time that actually passed.
  Traffic? _lastShownTotal;
  DateTime? _lastReadAt;

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    final readAt = DateTime.now();
    try {
      // Both halves every beat, not the one the setting picks: the totals card
      // needs the pair, and the Core is the only place the direct half exists.
      final [all, proxy] = await Future.wait([
        _readTraffic(() => _core.getTotalTraffic(false)),
        _readTraffic(() => _core.getTotalTraffic(true)),
      ]);
      if (all == null || proxy == null) {
        // A failed read moves neither the baseline nor the window.
        return;
      }
      ref.read(trafficTotalsProvider.notifier).value = (all: all, proxy: proxy);
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final shown = onlyStatisticsProxy ? proxy : all;
      ref.read(totalTrafficProvider.notifier).value = shown;
      _addSpeedSample(shown, readAt);
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  /// The Core refreshes its own one-second window on its own ticker, so asking
  /// it for "the last second" every second reads the same window twice as often
  /// as it reads a fresh one — the number stutters and sometimes repeats. The
  /// totals only ever grow, so the difference between two reads over the time
  /// between them is the average speed of that window, whichever beat it lands
  /// on.
  void _addSpeedSample(Traffic shown, DateTime readAt) {
    final last = _lastShownTotal;
    final lastAt = _lastReadAt;
    _lastShownTotal = shown;
    _lastReadAt = readAt;
    if (last == null || lastAt == null) {
      return;
    }
    final rate = rateBetween(last, shown, readAt.difference(lastAt));
    if (rate == null) {
      return;
    }
    ref.read(trafficsProvider.notifier).addTraffic(rate);
  }

  /// Bytes per second between two readings of the same running total, or null
  /// when the window says more about the sampling than about the traffic: a
  /// window shorter than a beat divides noise, a long one means the app was
  /// paused, and a total that went backwards means the Core restarted.
  @visibleForTesting
  static Traffic? rateBetween(Traffic last, Traffic next, Duration window) {
    if (window < _minRateWindow || window > _maxRateWindow) {
      return null;
    }
    final up = next.up - last.up;
    final down = next.down - last.down;
    if (up < 0 || down < 0) {
      return null;
    }
    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    return Traffic(up: (up / seconds).round(), down: (down / seconds).round());
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
