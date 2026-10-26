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
import 'package:gainer_mobile/ui/features/access/passkeys_screen.dart';

const _userId = '10000000-0000-4000-8000-000000000001';

final _configuration = MobileAppConfiguration(
  api: Uri.parse('https://api.example.test'),
);

void main() {
  testWidgets('lists passkeys and adds one with the system sheet', (
    tester,
  ) async {
    final server = _PasskeyServer()
      ..passkeys.add(
        ApiPasskey(
          id: 'first',
          name: 'iPad',
          createdAt: DateTime.utc(2026, 10, 1, 12),
        ),
      );
    final platform = _FakePasskeys();
    final controller = await _signedIn(tester, server, platform);

    await _pumpScreen(tester, controller);
    expect(find.text('iPad'), findsOneWidget);
    expect(find.text('Erstellt am 01.10.2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Passkey hinzufügen'));
    await tester.pumpAndSettle();

    expect(platform.created, [('gainer.markfort.xyz', 'athlete@example.test')]);
    expect(server.registeredNames, ['Gainer iPhone']);
    expect(find.text('Gainer iPhone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for the password when the sign-in is no longer fresh', (
    tester,
  ) async {
    final server = _PasskeyServer()..requirePassword = true;
    final platform = _FakePasskeys();
    final controller = await _signedIn(tester, server, platform);

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('Passkey hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Passwort bestätigen'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField), 'password');
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(server.passwords, [null, 'password']);
    expect(server.registeredNames, ['Gainer iPhone']);
    expect(find.text('Gainer iPhone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong password is reported and adds nothing', (tester) async {
    final server = _PasskeyServer()..requirePassword = true;
    final controller = await _signedIn(tester, server, _FakePasskeys());

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('Passkey hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'wrong');
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(server.registeredNames, isEmpty);
    expect(find.text('Das Passwort war falsch.'), findsOneWidget);
  });

  testWidgets('keeps the password field alive while the dialog fades out', (
    tester,
  ) async {
    final server = _PasskeyServer()..requirePassword = true;
    final controller = await _signedIn(tester, server, _FakePasskeys());

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('Passkey hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'password');
    await tester.tap(find.text('Weiter'));
    // Mitten in der Ausblend-Animation liegt das Feld noch im Baum.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    // Ein entsorgter Controller wirft bei jeder weiteren Nutzung, etwa wenn
    // die Tastatur beim Ausblenden einen Neuaufbau auslöst.
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(field.controller!),
      returnsNormally,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(server.passwords, [null, 'password']);
  });

  testWidgets('cancelling the password prompt adds nothing', (tester) async {
    final server = _PasskeyServer()..requirePassword = true;
    final controller = await _signedIn(tester, server, _FakePasskeys());

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('Passkey hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(server.passwords, [null]);
    expect(server.registeredNames, isEmpty);
    expect(find.text('Das Passwort war falsch.'), findsNothing);
  });

  testWidgets('cancelling the system sheet adds nothing', (tester) async {
    final server = _PasskeyServer();
    final platform = _FakePasskeys()..cancel = true;
    final controller = await _signedIn(tester, server, platform);

    await _pumpScreen(tester, controller);
    expect(find.text('Passkey hinzufügen'), findsOneWidget);
    await tester.tap(find.text('Passkey hinzufügen'));
    await tester.pumpAndSettle();

    expect(server.registeredNames, isEmpty);
    expect(find.text('Passkey hinzufügen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe and confirm removes a passkey', (tester) async {
    final server = _PasskeyServer()
      ..passkeys.add(
        ApiPasskey(
          id: 'first',
          name: 'iPad',
          createdAt: DateTime.utc(2026, 10, 1, 12),
        ),
      );
    final controller = await _signedIn(tester, server, _FakePasskeys());

    await _pumpScreen(tester, controller);
    await tester.drag(find.text('iPad'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();

    expect(server.deleted, ['first']);
    expect(find.text('iPad'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  MobileAuthController controller,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    CupertinoApp(
      theme: GainerTheme.light,
      home: PasskeysScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<MobileAuthController> _signedIn(
  WidgetTester tester,
  _PasskeyServer server,
  _FakePasskeys platform,
) async {
  final controller = MobileAuthController(
    configuration: _configuration,
    apiFactory: (configuration) => _PasskeyApi(configuration, server),
    secureSessions: _MemorySecureSession(),
    passkeys: platform,
    nativeFeatures: _QuietNativeFeatures(),
    accountDatabaseFactory: (_) async => LocalDatabase(NativeDatabase.memory()),
    installationDatabaseFactory: () async =>
        LocalDatabase(NativeDatabase.memory()),
  );
  addTearDown(controller.dispose);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await controller.initialize();
  await controller.login('athlete@example.test', 'password');
  expect(controller.state, MobileAuthState.signedIn);
  return controller;
}

class _PasskeyServer {
  final passkeys = <ApiPasskey>[];
  final registeredNames = <String?>[];
  final deleted = <String>[];
  final passwords = <String?>[];
  bool requirePassword = false;
}

class _PasskeyApi extends ApiClient {
  _PasskeyApi(ApiConfiguration configuration, this.server)
    : super(configuration: configuration);

  final _PasskeyServer server;

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
  Future<ApiSession?> getSession() async => const ApiSession(
    userId: _userId,
    email: 'athlete@example.test',
    isAccountOperator: false,
  );

  @override
  Uint8List createSecureCheckpoint(ApiSession session) =>
      Uint8List.fromList(session.userId.codeUnits);

  @override
  Future<List<ApiPasskey>> listPasskeys() async =>
      List.unmodifiable(server.passkeys);

  @override
  Future<ApiPasskeyOptions> passkeyCreationOptions({String? password}) async {
    server.passwords.add(password);
    if (server.requirePassword && password != 'password') {
      throw const ApiException(
        statusCode: 403,
        code: 'reauthentication_required',
        message: 'Confirm your password to add a passkey.',
      );
    }
    return const ApiPasskeyOptions(
      optionsJson: '{"rp":{"id":"gainer.markfort.xyz"},"user":{"id":"YWJj","name":"athlete@example.test"},"challenge":"AQID"}',
      state: 'state',
    );
  }

  @override
  Future<ApiPasskey> registerPasskey({
    required String credentialJson,
    required String state,
    String? name,
  }) async {
    server.registeredNames.add(name);
    final passkey = ApiPasskey(
      id: 'second',
      name: name ?? 'iPhone',
      createdAt: DateTime.utc(2026, 10, 20, 12),
    );
    server.passkeys.add(passkey);
    return passkey;
  }

  @override
  Future<void> deletePasskey(String id) async => server.deleted.add(id);
}

class _FakePasskeys implements PasskeyPlatform {
  bool cancel = false;
  final created = <(String, String)>[];

  @override
  Future<PlatformPasskeyRegistration?> createPasskey({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List userId,
    required String userName,
  }) async {
    if (cancel) return null;
    created.add((relyingPartyId, userName));
    return PlatformPasskeyRegistration(
      credentialId: Uint8List.fromList([1]),
      clientDataJson: Uint8List.fromList([2]),
      attestationObject: Uint8List.fromList([3]),
    );
  }

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
