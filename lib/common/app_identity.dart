import 'dart:io';

import 'package:flutter/services.dart';

/// What the Finder would show for a process: its app name and its icon.
class AppIdentity {
  const AppIdentity({required this.name, required this.icon});

  final String? name;
  final Uint8List? icon;
}

/// Resolves an executable to the app bundle that contains it, once per bundle.
/// The work happens in the runner — the name can live in a localized
/// InfoPlist.strings and the icon in an Assets.car, neither of which Dart can
/// read — so a miss simply leaves the row showing the process name.
class AppIdentities {
  static const _channel = MethodChannel('fl_clash/app_identity');

  static final _cache = <String, Future<AppIdentity?>>{};

  static Future<AppIdentity?> of(String executable) {
    if (!Platform.isMacOS) {
      return Future.value(null);
    }
    final bundle = _bundleOf(executable);
    if (bundle == null) {
      return Future.value(null);
    }
    return _cache.putIfAbsent(bundle, () => _resolve(bundle));
  }

  static Future<AppIdentity?> _resolve(String bundle) async {
    try {
      final payload = await _channel.invokeMapMethod<String, Object?>(
        'resolve',
        {'path': bundle},
      );
      if (payload == null) {
        return null;
      }
      final raw = payload['icon'];
      final icon = raw is Uint8List && raw.isNotEmpty ? raw : null;
      final name = (payload['name'] as String?)?.trim() ?? '';
      if (name.isEmpty && icon == null) {
        return null;
      }
      return AppIdentity(name: name.isEmpty ? null : name, icon: icon);
    } catch (_) {
      return null;
    }
  }

  /// The `.app` an executable sits in, or null for a plain binary such as
  /// `/usr/bin/curl`.
  static String? _bundleOf(String executable) {
    var path = executable;
    while (path.isNotEmpty && path != '/' && !path.endsWith('.app')) {
      final index = path.lastIndexOf('/');
      if (index <= 0) {
        return null;
      }
      path = path.substring(0, index);
    }
    return path.endsWith('.app') ? path : null;
  }
}
