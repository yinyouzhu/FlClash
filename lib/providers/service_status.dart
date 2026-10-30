import 'package:fl_clash/common/mixin.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'config.dart';
import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/service_status.g.dart';

@Riverpod(keepAlive: true)
class ServiceStatus extends _$ServiceStatus
    with RoutedProbe<ServiceTarget, ServiceCheck> {
  @override
  RoutedProbeState<ServiceTarget, ServiceCheck> build() => buildProbe();

  @override
  bool isFailure(ServiceCheck value) =>
      value.status == ServiceProbeStatus.timeout ||
      value.status == ServiceProbeStatus.failed;

  @override
  Future<Map<ServiceTarget, ProbeAnswer<ServiceCheck>>> probe(
    ServiceTarget target,
    RouteState route,
  ) async {
    final checks = await checkServices(
      ref.read(coreHandlerProvider),
      proxyName: route.proxied ? '' : directOutbound,
      targets: [target],
    );
    final check = checks[target];
    if (check != null) {
      ref
          .read(serviceLatencyHistoryProvider.notifier)
          .record(target, check);
    }
    return {
      if (check != null)
        target: ProbeAnswer(
          value: check,
          coreEpoch: check.coreEpoch,
          routeVersion: check.routeVersion,
          hits: check.hits,
        ),
    };
  }
}

/// How many probes a service's sparkline keeps. Loon's own card draws about
/// that many points across its width, which is the number to match.
const serviceLatencySamples = 18;

/// The delay each service answered with, most recent last, so the card can
/// draw a line instead of a bare number. A -1 stands for a probe that came
/// back without a delay — the line breaks there rather than claiming a zero.
@Riverpod(keepAlive: true)
class ServiceLatencyHistory extends _$ServiceLatencyHistory {
  @override
  Map<ServiceTarget, List<double>> build() => const {};

  void record(ServiceTarget target, ServiceCheck check) {
    final delay = check.status == ServiceProbeStatus.available
        ? (check.delay?.toDouble() ?? -1)
        : -1.0;
    final previous = state[target] ?? const <double>[];
    final next = [...previous, delay];
    state = {
      ...state,
      target: next.length > serviceLatencySamples
          ? next.sublist(next.length - serviceLatencySamples)
          : next,
    };
  }

  void clear() {
    if (state.isNotEmpty) {
      state = const {};
    }
  }
}

/// How many of [enabledServiceTargets] the dashboard card has room for, which
/// its sheet marks as shown there.
@Riverpod(keepAlive: true)
class ShownServiceCount extends _$ShownServiceCount
    with AutoDisposeNotifierMixin {
  @override
  int build() => 2;
}

@riverpod
List<ServiceTarget> serviceTargets(Ref ref) {
  final order = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.serviceOrder)),
  );
  return orderServiceTargets(order.value);
}

@riverpod
List<ServiceTarget> enabledServiceTargets(Ref ref) {
  final targets = ref.watch(serviceTargetsProvider);
  final disabled = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.disabledServices)),
  );
  final enabled = [
    for (final target in targets)
      if (!disabled.value.contains(target.id)) target,
  ];
  return enabled.isEmpty ? targets : enabled;
}
