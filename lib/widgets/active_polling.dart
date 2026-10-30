import 'dart:async';

import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/inherited.dart';
import 'package:flutter/widgets.dart';

typedef PollGuard = bool Function();

mixin ActivePollingMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _isForeground = false;
  bool _isPageActive = true;
  bool _isPolling = false;
  int _pollGeneration = 0;

  Duration get pollInterval;

  bool get pollOnStart => true;

  Future<void> poll(PollGuard isCurrent);

  bool get canPoll => mounted && _isForeground && _isPageActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground = _showsData(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncPolling();
      }
    });
  }

  /// Whether the app is in a state where its numbers should keep moving.
  ///
  /// A desktop window that loses focus is `inactive`, not hidden, and it stays
  /// on screen: treating that as gone froze every polled number until the next
  /// click brought the window forward again, which is exactly how it looked —
  /// the panel only refreshed when it was clicked.
  bool _showsData(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed => true,
    AppLifecycleState.inactive => system.isDesktop,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The overlay turns tickers off on a page an opaque route covers once
    // that route has finished moving in.
    final isPageActive =
        PageActivityScope.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_isPageActive == isPageActive) {
      return;
    }
    _isPageActive = isPageActive;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isForeground = _showsData(state);
    if (_isForeground == isForeground) {
      return;
    }
    _isForeground = isForeground;
    _syncPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isForeground = false;
    stopPolling();
    super.dispose();
  }

  void startPolling() {
    if (!canPoll || _isPolling) {
      return;
    }
    _isPolling = true;
    final generation = ++_pollGeneration;
    if (pollOnStart) {
      unawaited(_runPoll(generation));
      return;
    }
    _schedulePoll(generation);
  }

  void stopPolling() {
    _isPolling = false;
    _pollGeneration++;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void restartPolling() {
    stopPolling();
    _syncPolling();
  }

  void _syncPolling() {
    if (canPoll) {
      startPolling();
    } else {
      stopPolling();
    }
  }

  bool _isCurrentPoll(int generation) =>
      canPoll && _isPolling && generation == _pollGeneration;

  void _schedulePoll(int generation) {
    _pollTimer = Timer(pollInterval, () {
      _pollTimer = null;
      if (_isCurrentPoll(generation)) {
        unawaited(_runPoll(generation));
      }
    });
  }

  Future<void> _runPoll(int generation) async {
    try {
      await poll(() => _isCurrentPoll(generation));
    } catch (error) {
      commonPrint.log(
        '$runtimeType poll error: $error',
        logLevel: LogLevel.warning,
      );
    } finally {
      if (_isCurrentPoll(generation)) {
        _schedulePoll(generation);
      }
    }
  }
}

typedef TickWidgetBuilder = Widget Function(BuildContext context, int tick);

class TickBuilder extends StatefulWidget {
  final Duration duration;
  final TickWidgetBuilder builder;

  const TickBuilder({super.key, required this.duration, required this.builder})
    : assert(duration > Duration.zero);

  @override
  State<TickBuilder> createState() => _TickBuilderState();
}

class _TickBuilderState extends State<TickBuilder>
    with WidgetsBindingObserver, ActivePollingMixin<TickBuilder> {
  int _tick = 0;

  @override
  Duration get pollInterval => widget.duration;

  @override
  bool get pollOnStart => false;

  @override
  Future<void> poll(PollGuard isCurrent) async {
    setState(() {
      _tick++;
    });
  }

  // Resuming restarts the interval, so a desktop window that loses focus more
  // often than that would otherwise never tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final couldPoll = canPoll;
    super.didChangeAppLifecycleState(state);
    if (!couldPoll && canPoll) {
      setState(() {
        _tick++;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TickBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      restartPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _tick);
  }
}
