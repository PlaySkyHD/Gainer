import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_features_platform.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/access/connected_apps_screen.dart';

const _userId = '10000000-0000-4000-8000-000000000001';
const _chatGptId = '20000000-0000-4000-8000-000000000001';
const _claudeId = '20000000-0000-4000-8000-000000000002';

final _configuration = MobileAppConfiguration(
  api: Uri.parse('https://api.example.test'),
);

ApiConnectorSession _chatGpt() => ApiConnectorSession(
  id: _chatGptId,
  name: 'ChatGPT',
  createdAt: DateTime.utc(2026, 11, 20, 12),
  lastUsedAt: DateTime.utc(2026, 11, 26, 12),
);

ApiConnectorSession _claude() => ApiConnectorSession(
  id: _claudeId,
  name: 'Claude',
  createdAt: DateTime.utc(2026, 11, 1, 12),
  lastUsedAt: DateTime.utc(2026, 11, 2, 12),
);

void main() {
  testWidgets('lists connected apps with German dates', (tester) async {
    final server = _ConnectorServer()..connectors.addAll([_chatGpt()]);
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);

    expect(find.text('Verbundene Apps'), findsWidgets);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(
      find.text('Verbunden am 20.11.2026 · zuletzt genutzt 26.11.2026'),
      findsOneWidget,
    );
    expect(find.text('Kein Assistent verbunden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state explains the setup and copies the MCP address', (
    tester,
  ) async {
    final server = _ConnectorServer();
    final controller = await _signedIn(tester, server);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpScreen(tester, controller);

    expect(find.text('Kein Assistent verbunden'), findsOneWidget);
    expect(find.textContaining('ChatGPT'), findsOneWidget);
    expect(find.text('https://api.example.test/api/v1/mcp'), findsOneWidget);

    await tester.tap(find.text('https://api.example.test/api/v1/mcp'));
    await tester.pumpAndSettle();

    expect(copied, 'https://api.example.test/api/v1/mcp');
    expect(find.text('Kopiert'), findsOneWidget);
  });

  testWidgets('tap and "Trennen" disconnects and reloads the list', (
    tester,
  ) async {
    final server = _ConnectorServer()
      ..connectors.addAll([_chatGpt(), _claude()]);
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    expect(server.listCalls, 1);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();

    expect(server.deleted, [_chatGptId]);
    expect(server.listCalls, 2);
    expect(find.text('ChatGPT'), findsNothing);
    expect(find.text('Claude'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe and confirm disconnects and shows the empty state', (
    tester,
  ) async {
    final server = _ConnectorServer()..connectors.add(_chatGpt());
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    await tester.drag(find.text('ChatGPT'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('ChatGPT trennen?'), findsOneWidget);
    await tester.tap(find.text('Trennen').last);
    await tester.pumpAndSettle();

    expect(server.deleted, [_chatGptId]);
    expect(server.listCalls, 2);
    expect(find.text('Kein Assistent verbunden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers no second disconnect while one is running', (
    tester,
  ) async {
    final server = _ConnectorServer()
      ..connectors.addAll([_chatGpt(), _claude()])
      ..holdDelete = true;
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trennen'));
    await tester.pump();

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    expect(find.text('Trennen'), findsNothing);
    await tester.drag(find.text('Claude'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Claude trennen?'), findsNothing);

    server.release();
    await tester.pumpAndSettle();
    expect(server.deleted, [_chatGptId]);
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('a connection already gone counts as disconnected', (
    tester,
  ) async {
    final server = _ConnectorServer()
      ..connectors.add(_chatGpt())
      ..deleteError = const ApiException(
        statusCode: 404,
        code: 'connector_not_found',
        message: 'Not found.',
      );
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Die Verbindung konnte nicht getrennt werden.'),
      findsNothing,
    );
    expect(server.listCalls, 2);
  });

  testWidgets('a failed disconnect is reported and the list reloaded', (
    tester,
  ) async {
    final server = _ConnectorServer()
      ..connectors.add(_chatGpt())
      ..deleteError = const ApiException(
        statusCode: 503,
        code: 'http_503',
        message: 'unavailable',
      );
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Die Verbindung konnte nicht getrennt werden.'),
      findsOneWidget,
    );
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(server.listCalls, 2);
  });

  testWidgets('a failed load shows the error and retries', (tester) async {
    final server = _ConnectorServer()
      ..connectors.add(_chatGpt())
      ..failList = true;
    final controller = await _signedIn(tester, server);

    await _pumpScreen(tester, controller);
    expect(
      find.text(
        'Verbundene Apps konnten nicht geladen werden. Prüfe deine Verbindung.',
      ),
      findsOneWidget,
    );
    expect(find.text('ChatGPT'), findsNothing);
    expect(find.text('Kein Assistent verbunden'), findsNothing);

    server.failList = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsNothing);
  });

  testWidgets('offline shows the error state without calling the server', (
    tester,
  ) async {
    final server = _ConnectorServer()
      ..connectors.add(_chatGpt())
      ..offline = true;
    final controller = await _offline(tester, server);

    await _pumpScreen(tester, controller);

    expect(
      find.text('Verbundene Apps lassen sich nur mit Verbindung verwalten.'),
      findsOneWidget,
    );
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('ChatGPT'), findsNothing);
    expect(server.listCalls, 0);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('no overflow at text scale $scale', (tester) async {
      final server = _ConnectorServer()
        ..connectors.addAll([_chatGpt(), _claude()]);
      final controller = await _signedIn(tester, server);

      await _pumpScreen(tester, controller, textScale: scale, width: 375);
      for (final name in ['ChatGPT', 'Claude']) {
        await tester.scrollUntilVisible(
          find.text(name),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state has no overflow at text scale $scale', (
      tester,
    ) async {
      final controller = await _signedIn(tester, _ConnectorServer());

      await _pumpScreen(tester, controller, textScale: scale, width: 375);
      const url = 'https://api.example.test/api/v1/mcp';
      await tester.scrollUntilVisible(
        find.text(url),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(url), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  MobileAuthController controller, {
  double textScale = 1,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    CupertinoApp(
      theme: GainerTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ConnectedAppsScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

MobileAuthController _controller(
  _ConnectorServer server,
  _MemorySecureSession secure,
) {
  final controller = MobileAuthController(
    configuration: _configuration,
    apiFactory: (configuration) => _ConnectorApi(configuration, server),
    secureSessions: secure,
    passkeys: _NoPasskeys(),
    nativeFeatures: _QuietNativeFeatures(),
    accountDatabaseFactory: (_) async => LocalDatabase(NativeDatabase.memory()),
    installationDatabaseFactory: () async =>
        LocalDatabase(NativeDatabase.memory()),
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<MobileAuthController> _signedIn(
  WidgetTester tester,
  _ConnectorServer server,
) async {
  final controller = _controller(server, _MemorySecureSession());
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await controller.initialize();
  await controller.login('athlete@example.test', 'password');
  expect(controller.state, MobileAuthState.signedIn);
  return controller;
}

/// Öffnet das bekannte Konto aus dem gespeicherten Checkpoint, weil der Server
/// nicht erreichbar ist.
Future<MobileAuthController> _offline(
  WidgetTester tester,
  _ConnectorServer server,
) async {
  final secure = _MemorySecureSession()
    ..value = Uint8List.fromList(_userId.codeUnits);
  final controller = _controller(server, secure);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await controller.initialize();
  expect(controller.account?.online, isFalse);
  return controller;
}

class _ConnectorServer {
  final connectors = <ApiConnectorSession>[];
  final deleted = <String>[];
  var listCalls = 0;
  bool failList = false;
  bool offline = false;
  bool holdDelete = false;
  ApiException? deleteError;
  final _hold = Completer<void>();

  /// Hält das Löschen an, bis der Test es mit [release] freigibt.
  Future<void> waitIfHeld() => holdDelete ? _hold.future : Future.value();

  void release() => _hold.complete();
}

class _ConnectorApi extends ApiClient {
  _ConnectorApi(ApiConfiguration configuration, this.server)
    : super(configuration: configuration);

  final _ConnectorServer server;

  @override
  void clearTokens() {}

  @override
  Future<ApiTokenResponse> login(ApiLoginRequest request) async =>
      const ApiTokenResponse(
        accessToken: 'access',
        expiresIn: 900,
        refreshToken: 'refresh',
      );

  @override
  Future<ApiSession?> getSession() async {
    if (server.offline) {
      throw const ApiException(
        statusCode: 503,
        code: 'http_503',
        message: 'unavailable',
      );
    }
    return const ApiSession(
      userId: _userId,
      email: 'athlete@example.test',
      isAccountOperator: false,
    );
  }

  @override
  Uint8List createSecureCheckpoint(ApiSession session) =>
      Uint8List.fromList(session.userId.codeUnits);

  @override
  ApiSessionCheckpoint restoreSecureCheckpoint(Uint8List bytes) =>
      ApiSessionCheckpoint(
        userId: String.fromCharCodes(bytes),
        email: 'athlete@example.test',
      );

  @override
  Future<List<ApiConnectorSession>> listConnectors() async {
    server.listCalls++;
    if (server.failList) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: 'offline',
      );
    }
    return List.unmodifiable(server.connectors);
  }

  @override
  Future<void> deleteConnector(String id) async {
    await server.waitIfHeld();
    server.deleted.add(id);
    if (server.deleteError case final error?) throw error;
    server.connectors.removeWhere((connector) => connector.id == id);
  }
}

class _NoPasskeys implements PasskeyPlatform {
  @override
  Future<PlatformPasskeyRegistration?> createPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List userId,
    required String userName,
  }) async => null;

  @override
  Future<PlatformPasskeyAssertion?> assertPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
  }) async => null;
}

class _MemorySecureSession implements SecureSessionPlatform {
  Uint8List? value;

  @override
  Future<void> clearCheckpoint(String apiOrigin) async => value = null;

  @override
  Future<Uint8List?> readCheckpoint(String apiOrigin) async => value;

  @override
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint) async =>
      value = Uint8List.fromList(checkpoint);
}

class _QuietNativeFeatures extends PigeonNativeFeaturesPlatform {
  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) async {}

  @override
  Future<void> clear({required int minimumGeneration}) async {}

  @override
  Future<void> endAll() async {}
}
