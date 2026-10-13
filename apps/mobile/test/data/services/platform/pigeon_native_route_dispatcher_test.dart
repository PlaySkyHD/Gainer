import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_route_dispatcher.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

class _RouteConsumer implements NativeRouteConsumer {
  final requests = <NativeAppRouteRequest>[];
  bool activeSession = true;
  bool enforceActiveAtDispatch = false;
  Completer<bool>? sessionGate;
  Completer<void>? sessionCheckStarted;
  Future<void> Function(NativeAppRouteRequest request)? routeHandler;

  @override
  Future<bool> hasActiveAccountSession() async {
    sessionCheckStarted?.complete();
    return sessionGate?.future ?? activeSession;
  }

  @override
  Future<void> onRouteRequested(NativeAppRouteRequest request) async {
    if (enforceActiveAtDispatch && !activeSession) {
      throw PlatformException(code: 'active_session_required');
    }
    requests.add(request);
    await routeHandler?.call(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Pigeon channel acknowledges only after an active scoped route completes',
    () async {
      final consumer = _RouteConsumer();
      final routeWork = Completer<void>();
      consumer.routeHandler = (_) => routeWork.future;
      final dispatcher = PigeonNativeRouteDispatcher(
        consumer: consumer,
        now: () => DateTime.utc(2026, 10, 12, 10),
      );
      addTearDown(dispatcher.dispose);

      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.gainer_mobile.MobileRouteFlutterApi.dispatchRoute',
        MobileRouteFlutterApi.pigeonChannelCodec,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var acknowledged = false;
      final responseFuture = messenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMessage(<Object?>[
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
            ]),
            null,
          )
          .then((response) {
            acknowledged = true;
            return channel.codec.decodeMessage(response);
          });
      await Future<void>.delayed(Duration.zero);
      expect(acknowledged, isFalse);
      routeWork.complete();
      expect(await responseFuture, isEmpty);

      expect(consumer.requests.single.destination, NativeAppRoute.checkIn);
      expect(consumer.requests.single.source, NativeRouteSource.widget);
    },
  );

  test('rejects manipulated and expired native routes', () async {
    final dispatcher = PigeonNativeRouteDispatcher(
      consumer: _RouteConsumer(),
      now: () => DateTime.utc(2026, 10, 12, 10),
    );
    addTearDown(dispatcher.dispose);

    await expectLater(
      dispatcher.dispatchRoute(
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
    await expectLater(
      dispatcher.dispatchRoute(
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

  test('propagates session-gate failures through the Pigeon channel', () async {
    final consumer = _RouteConsumer()..activeSession = false;
    final dispatcher = PigeonNativeRouteDispatcher(
      consumer: consumer,
      now: () => DateTime.utc(2026, 10, 12, 10),
    );
    addTearDown(dispatcher.dispose);

    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.gainer_mobile.MobileRouteFlutterApi.dispatchRoute',
      MobileRouteFlutterApi.pigeonChannelCodec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final response = await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMessage(<Object?>[
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
      ]),
      null,
    );
    final decoded = channel.codec.decodeMessage(response) as List<Object?>;
    expect(decoded.first, 'active_session_required');
    expect(consumer.requests, isEmpty);
  });

  test(
    'rechecks session after an account switch before route dispatch',
    () async {
      final consumer = _RouteConsumer()
        ..enforceActiveAtDispatch = true
        ..sessionGate = Completer<bool>()
        ..sessionCheckStarted = Completer<void>();
      final dispatcher = PigeonNativeRouteDispatcher(
        consumer: consumer,
        now: () => DateTime.utc(2026, 10, 12, 10),
      );
      addTearDown(dispatcher.dispose);
      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.gainer_mobile.MobileRouteFlutterApi.dispatchRoute',
        MobileRouteFlutterApi.pigeonChannelCodec,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final responseFuture = messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMessage(<Object?>[
          PlatformRoute(
            destination: 'training',
            source: 'widget',
            createdAtUtcEpochMilliseconds: DateTime.utc(
              2026,
              10,
              12,
              9,
              59,
            ).millisecondsSinceEpoch,
          ),
        ]),
        null,
      );

      await consumer.sessionCheckStarted!.future;
      consumer.activeSession = false;
      consumer.sessionGate!.complete(true);
      final response =
          channel.codec.decodeMessage(await responseFuture) as List<Object?>;

      expect(response.first, 'active_session_required');
      expect(consumer.requests, isEmpty);
    },
  );
}
