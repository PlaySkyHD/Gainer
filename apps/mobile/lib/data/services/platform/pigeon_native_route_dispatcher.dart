import 'package:flutter/services.dart';

import 'generated/mobile_platform_api.dart';
import 'platform_ports.dart';

/// Receives untrusted route requests from widgets, Live Activities and Shortcuts.
/// Dispatch waits for the active account session before entering a feature.
class PigeonNativeRouteDispatcher extends MobileRouteFlutterApi {
  PigeonNativeRouteDispatcher({
    required this._consumer,
    BinaryMessenger? binaryMessenger,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    MobileRouteFlutterApi.setUp(this, binaryMessenger: binaryMessenger);
  }

  final NativeRouteConsumer _consumer;
  final DateTime Function() _now;

  void dispose({BinaryMessenger? binaryMessenger}) {
    MobileRouteFlutterApi.setUp(null, binaryMessenger: binaryMessenger);
  }

  @override
  Future<void> dispatchRoute(PlatformRoute route) async {
    final destination = switch (route.destination) {
      'training' => NativeAppRoute.training,
      'checkIn' => NativeAppRoute.checkIn,
      'nutrition' => NativeAppRoute.nutrition,
      _ => throw PlatformException(code: 'invalid_route'),
    };
    final source = switch (route.source) {
      'widget' => NativeRouteSource.widget,
      'liveActivity' => NativeRouteSource.liveActivity,
      'shortcut' => NativeRouteSource.shortcut,
      _ => throw PlatformException(code: 'invalid_route_source'),
    };
    final createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
      route.createdAtUtcEpochMilliseconds,
      isUtc: true,
    );
    final age = _now().toUtc().difference(createdAtUtc);
    if (age.isNegative || age > const Duration(minutes: 10)) {
      throw PlatformException(code: 'expired_route');
    }

    if (!await _consumer.hasActiveAccountSession()) {
      throw PlatformException(code: 'active_session_required');
    }
    await _consumer.onRouteRequested(
      NativeAppRouteRequest(
        destination: destination,
        source: source,
        createdAtUtc: createdAtUtc,
      ),
    );
  }
}
