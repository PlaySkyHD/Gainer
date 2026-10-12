import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_route_dispatcher.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

class _RouteConsumer implements NativeRouteConsumer {
  final requests = <NativeAppRouteRequest>[];
  bool activeSession = true;

  @override
  Future<bool> hasActiveAccountSession() async => activeSession;

  @override
  Future<void> onRouteRequested(NativeAppRouteRequest request) async {
    requests.add(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dispatches fresh typed routes only after the active account session loads',
    () async {
      final consumer = _RouteConsumer();
      final dispatcher = PigeonNativeRouteDispatcher(
        consumer: consumer,
        now: () => DateTime.utc(2026, 10, 12, 10),
      );
      addTearDown(dispatcher.dispose);

      dispatcher.dispatchRoute(
        PlatformRoute(
          destination: 'checkIn',
          source: 'widget',
          createdAtUtcEpochMilliseconds: DateTime.utc(
            2026,
            10,
            12,
            9,
            59,
          ).millisecondsSinceEpoch,
        ),
      );
      await dispatcher.lastDispatch;

      expect(consumer.requests.single.destination, NativeAppRoute.checkIn);
      expect(consumer.requests.single.source, NativeRouteSource.widget);
    },
  );

  test('rejects manipulated and expired native routes', () {
    final dispatcher = PigeonNativeRouteDispatcher(
      consumer: _RouteConsumer(),
      now: () => DateTime.utc(2026, 10, 12, 10),
    );
    addTearDown(dispatcher.dispose);

    expect(
      () => dispatcher.dispatchRoute(
        PlatformRoute(
          destination: 'deleteAllData',
          source: 'shortcut',
          createdAtUtcEpochMilliseconds: DateTime.utc(
            2026,
            10,
            12,
            9,
            59,
          ).millisecondsSinceEpoch,
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(
      () => dispatcher.dispatchRoute(
        PlatformRoute(
          destination: 'training',
          source: 'shortcut',
          createdAtUtcEpochMilliseconds: DateTime.utc(
            2026,
            10,
            12,
            9,
          ).millisecondsSinceEpoch,
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test(
    'keeps valid routes from entering a feature without an active account',
    () async {
      final consumer = _RouteConsumer()..activeSession = false;
      final dispatcher = PigeonNativeRouteDispatcher(
        consumer: consumer,
        now: () => DateTime.utc(2026, 10, 12, 10),
      );
      addTearDown(dispatcher.dispose);

      dispatcher.dispatchRoute(
        PlatformRoute(
          destination: 'training',
          source: 'shortcut',
          createdAtUtcEpochMilliseconds: DateTime.utc(
            2026,
            10,
            12,
            9,
            59,
          ).millisecondsSinceEpoch,
        ),
      );

      await expectLater(
        dispatcher.lastDispatch,
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'active_session_required',
          ),
        ),
      );
      expect(consumer.requests, isEmpty);
    },
  );
}
