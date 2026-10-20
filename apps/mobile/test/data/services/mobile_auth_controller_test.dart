import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_features_platform.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching login accounts replaces the active account scope', () async {
    final secure = _MemorySecureSession();
    final databases = <String, LocalDatabase>{};
    final apiFactory = _FakeApiFactory();
    final controller = _controller(
      secure: secure,
      databases: databases,
      apiFactory: apiFactory,
    );
    try {
      await controller.initialize();
      expect(controller.state, MobileAuthState.signedOut);

      await controller.login('a@example.test', 'password');
      expect(controller.state, MobileAuthState.signedIn);
      expect(controller.account?.session.userId, _accountA);
      expect(controller.account?.store.accountId, _accountA);

      await controller.login('b@example.test', 'password');
      expect(controller.state, MobileAuthState.signedIn);
      expect(controller.account?.session.userId, _accountB);
      expect(controller.account?.store.accountId, _accountB);
      expect(databases.keys, {_accountA, _accountB});
      expect(secure.value, isNotNull);
    } finally {
      await controller.logout();
      controller.dispose();
    }
  });

  test('logout everywhere signs out only after the server agreed', () async {
    final secure = _MemorySecureSession();
    final apiFactory = _FakeApiFactory()..rejectLogoutAll = true;
    final controller = _controller(
      secure: secure,
      databases: {},
      apiFactory: apiFactory,
    );
    try {
      await controller.initialize();
      await controller.login('a@example.test', 'password');

      await expectLater(
        controller.logoutEverywhere(),
        throwsA(isA<ApiException>()),
      );
      expect(controller.state, MobileAuthState.signedIn);
      expect(secure.value, isNotNull);

      apiFactory.rejectLogoutAll = false;
      await controller.logoutEverywhere();
      expect(apiFactory.logoutAllCalls, 2);
      expect(controller.state, MobileAuthState.signedOut);
      expect(secure.value, isNull);
    } finally {
      controller.dispose();
    }
  });

  test(
    'passkey sign-in opens the account and cancelling changes nothing',
    () async {
      final secure = _MemorySecureSession();
      final databases = <String, LocalDatabase>{};
      final apiFactory = _FakeApiFactory();
      final passkeys = _FakePasskeys()..cancel = true;
      final controller = _controller(
        secure: secure,
        databases: databases,
        apiFactory: apiFactory,
        passkeys: passkeys,
      );
      try {
        await controller.initialize();
        await controller.loginWithPasskey();
        expect(passkeys.assertions, 1);
        expect(controller.state, MobileAuthState.signedOut);
        expect(controller.errorMessage, isNull);
        expect(secure.value, isNull);

        passkeys.cancel = false;
        await controller.loginWithPasskey();
        expect(controller.state, MobileAuthState.signedIn);
        expect(controller.account?.session.userId, _accountB);
        expect(apiFactory.loginDeviceNames, ['Gainer iPhone']);
        expect(secure.value, isNotNull);
      } finally {
        await controller.logout();
        controller.dispose();
      }
    },
  );

  test('passkey sign-in reports unknown passkeys and offline state', () async {
    final apiFactory = _FakeApiFactory(rejectPassword: true);
    final controller = _controller(
      secure: _MemorySecureSession(),
      databases: <String, LocalDatabase>{},
      apiFactory: apiFactory,
    );
    try {
      await controller.initialize();
      await controller.loginWithPasskey();
      expect(controller.state, MobileAuthState.signedOut);
      expect(controller.errorMessage, contains('keinem aktiven Konto'));

      apiFactory.offline = true;
      await controller.loginWithPasskey();
      expect(controller.errorMessage, contains('Prüfe die Verbindung'));
      expect(() => controller.listPasskeys(), throwsStateError);
    } finally {
      controller.dispose();
    }
  });

  test(
    'a rejected device session signs out with a hint to sign in again',
    () async {
      final secure = _MemorySecureSession();
      final databases = <String, LocalDatabase>{};
      final apiFactory = _FakeApiFactory();
      final controller = _controller(
        secure: secure,
        databases: databases,
        apiFactory: apiFactory,
      );
      try {
        await controller.initialize();
        await controller.login('a@example.test', 'password');
        expect(controller.state, MobileAuthState.signedIn);
        expect(apiFactory.loginDeviceNames, ['Gainer iPhone']);
        expect(secure.value, isNotNull);

        controller.account!.api.onSessionRejected!();
        await pumpEventQueue();

        expect(controller.state, MobileAuthState.signedOut);
        expect(controller.account, isNull);
        expect(secure.value, isNull);
        expect(controller.errorMessage, contains('Anmeldung ist abgelaufen'));
        expect(databases.keys, {_accountA});
      } finally {
        await controller.logout();
        controller.dispose();
      }
    },
  );

  test(
    '401 shows a safe login error and never opens an account scope',
    () async {
      final secure = _MemorySecureSession();
      final databases = <String, LocalDatabase>{};
      final apiFactory = _FakeApiFactory(rejectPassword: true);
      final controller = _controller(
        secure: secure,
        databases: databases,
        apiFactory: apiFactory,
      );
      try {
        await controller.initialize();
        await controller.login('a@example.test', 'wrong');
        expect(controller.state, MobileAuthState.signedOut);
        expect(controller.account, isNull);
        expect(
          controller.errorMessage,
          'E-Mail-Adresse oder Passwort stimmen nicht.',
        );
        expect(databases, isEmpty);
        expect(secure.value, isNull);
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'restored online session notifies the app after scope creation',
    () async {
      final secure = _MemorySecureSession()
        ..value = Uint8List.fromList(_accountA.codeUnits);
      final databases = <String, LocalDatabase>{};
      final controller = _controller(
        secure: secure,
        databases: databases,
        apiFactory: _FakeApiFactory(),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      try {
        await controller.initialize();
        expect(controller.state, MobileAuthState.signedIn);
        expect(controller.account?.session.userId, _accountA);
        expect(notifications, greaterThan(0));
      } finally {
        await controller.logout();
        controller.dispose();
      }
    },
  );

  test(
    'a valid secure checkpoint restores only a known account offline',
    () async {
      final secure = _MemorySecureSession();
      final firstDatabases = <String, LocalDatabase>{};
      final apiFactory = _FakeApiFactory();
      final first = _controller(
        secure: secure,
        databases: firstDatabases,
        apiFactory: apiFactory,
      );
      await first.initialize();
      await first.login('a@example.test', 'password');
      expect(first.account?.session.userId, _accountA);
      final checkpoint = secure.value;
      await first.logout();
      secure.value = checkpoint;
      first.dispose();
      apiFactory.offline = true;

      final offlineDatabases = <String, LocalDatabase>{};
      final offline = _controller(
        secure: secure,
        databases: offlineDatabases,
        apiFactory: apiFactory,
      );
      try {
        await offline.initialize();
        expect(offline.state, MobileAuthState.offlineKnownUser);
        expect(offline.account?.session.userId, _accountA);
        expect(offline.account?.online, isFalse);
        expect(offlineDatabases.keys, {_accountA});
      } finally {
        await offline.logout();
        offline.dispose();
      }
    },
  );

  group('native training route', () {
    NativeAppRouteRequest route({
      NativeRouteSource source = NativeRouteSource.liveActivity,
    }) => NativeAppRouteRequest(
      destination: NativeAppRoute.training,
      source: source,
      createdAtUtc: DateTime.now().toUtc(),
    );

    test(
      'Live Activity opens the active workout of the current account',
      () async {
        final secure = _MemorySecureSession();
        final controller = _controller(
          secure: secure,
          databases: <String, LocalDatabase>{},
          apiFactory: _FakeApiFactory(),
        );
        try {
          await controller.initialize();
          await controller.login('a@example.test', 'password');
          final account = controller.account!;
          final workout = await account.training.startEmpty(title: 'Push');
          await account.activeWorkout.load();

          await controller.onRouteRequested(route());

          expect(controller.shell.selectedArea, MobileArea.training);
          expect(controller.shell.takeRequestedWorkout(), workout.workoutId);
          // Das offene Training bleibt; es wird nur nach vorn geholt.
          expect(controller.shell.takeRequestedCloseOverlays(), isFalse);
        } finally {
          await controller.logout();
          controller.dispose();
        }
      },
    );

    test(
      'Live Activity opens the running cardio session before a workout',
      () async {
        final controller = _controller(
          secure: _MemorySecureSession(),
          databases: <String, LocalDatabase>{},
          apiFactory: _FakeApiFactory(),
        );
        try {
          await controller.initialize();
          await controller.login('a@example.test', 'password');
          final account = controller.account!;
          await account.training.startEmpty(title: 'Push');
          await account.activeWorkout.load();
          await account.cardioSession.start();

          await controller.onRouteRequested(route());

          expect(controller.shell.selectedArea, MobileArea.training);
          expect(controller.shell.takeRequestedCardio(), isTrue);
          expect(controller.shell.takeRequestedWorkout(), isNull);
        } finally {
          await controller.logout();
          controller.dispose();
        }
      },
    );

    test('without an active workout only the training tab opens', () async {
      final controller = _controller(
        secure: _MemorySecureSession(),
        databases: <String, LocalDatabase>{},
        apiFactory: _FakeApiFactory(),
      );
      try {
        await controller.initialize();
        await controller.login('a@example.test', 'password');

        await controller.onRouteRequested(route());

        expect(controller.shell.selectedArea, MobileArea.training);
        expect(controller.shell.takeRequestedWorkout(), isNull);
      } finally {
        await controller.logout();
        controller.dispose();
      }
    });

    test('a widget route never opens a workout, only the tab', () async {
      final controller = _controller(
        secure: _MemorySecureSession(),
        databases: <String, LocalDatabase>{},
        apiFactory: _FakeApiFactory(),
      );
      try {
        await controller.initialize();
        await controller.login('a@example.test', 'password');
        final account = controller.account!;
        await account.training.startEmpty(title: 'Push');
        await account.activeWorkout.load();

        await controller.onRouteRequested(
          route(source: NativeRouteSource.widget),
        );

        expect(controller.shell.selectedArea, MobileArea.training);
        expect(controller.shell.takeRequestedWorkout(), isNull);
        // Offene Vollbilder schließen, sonst bliebe der Tab verdeckt.
        expect(controller.shell.takeRequestedCloseOverlays(), isTrue);
      } finally {
        await controller.logout();
        controller.dispose();
      }
    });

    test('a signed-out app rejects the route and mutates nothing', () async {
      final controller = _controller(
        secure: _MemorySecureSession(),
        databases: <String, LocalDatabase>{},
        apiFactory: _FakeApiFactory(),
      );
      try {
        await controller.initialize();
        expect(() => controller.onRouteRequested(route()), throwsStateError);

        expect(controller.shell.selectedArea, MobileArea.progress);
        expect(controller.shell.takeRequestedWorkout(), isNull);
      } finally {
        controller.dispose();
      }
    });

    test(
      'another account never receives the previous account workout',
      () async {
        final databases = <String, LocalDatabase>{};
        final controller = _controller(
          secure: _MemorySecureSession(),
          databases: databases,
          apiFactory: _FakeApiFactory(),
        );
        try {
          await controller.initialize();
          await controller.login('a@example.test', 'password');
          await controller.account!.training.startEmpty(title: 'Push');
          await controller.account!.activeWorkout.load();
          await controller.logout();

          await controller.login('b@example.test', 'password');
          await controller.onRouteRequested(route());

          expect(controller.account?.session.userId, _accountB);
          expect(controller.shell.takeRequestedWorkout(), isNull);
        } finally {
          await controller.logout();
          controller.dispose();
        }
      },
    );
  });
}

const _accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

MobileAuthController _controller({
  required _MemorySecureSession secure,
  required Map<String, LocalDatabase> databases,
  required _FakeApiFactory apiFactory,
  PasskeyPlatform? passkeys,
}) => MobileAuthController(
  passkeys: passkeys ?? _FakePasskeys(),
  configuration: MobileAppConfiguration(
    api: Uri.parse('https://api.example.test'),
  ),
  apiFactory: apiFactory.call,
  secureSessions: secure,
  nativeFeatures: _FakeNativeFeatures(),
  accountDatabaseFactory: (accountId) async => databases.putIfAbsent(
    accountId,
    () => LocalDatabase(NativeDatabase.memory()),
  ),
  installationDatabaseFactory: () async =>
      LocalDatabase(NativeDatabase.memory()),
);

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

class _FakeNativeFeatures extends PigeonNativeFeaturesPlatform {
  String? _monitoring;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<HeartRateStatus> readStatus(int afterSequence) async =>
      HeartRateStatus(monitoringSessionId: _monitoring);

  @override
  Future<void> startMonitoring(HeartRateMonitoringConfig config) async =>
      _monitoring = config.sessionId;

  @override
  Future<void> stopMonitoring(String sessionId) async => _monitoring = null;

  @override
  Future<void> publish(NeutralExtensionSnapshot snapshot) async {}

  @override
  Future<void> clear({required int minimumGeneration}) async {}

  @override
  Future<void> endAll() async {}
}

class _FakeApiFactory {
  _FakeApiFactory({this.rejectPassword = false});

  final bool rejectPassword;
  bool offline = false;
  final Map<String, ApiSession> sessions = {
    _accountA: const ApiSession(
      userId: _accountA,
      email: 'a@example.test',
      isAccountOperator: false,
    ),
    _accountB: const ApiSession(
      userId: _accountB,
      email: 'b@example.test',
      isAccountOperator: false,
    ),
  };
  ApiSession? activeSession;
  final loginDeviceNames = <String?>[];
  bool rejectLogoutAll = false;
  int logoutAllCalls = 0;

  ApiClient call(ApiConfiguration configuration) =>
      _FakeApiClient(configuration: configuration, factory: this);
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required super.configuration, required this.factory});

  final _FakeApiFactory factory;

  @override
  void clearTokens() => factory.activeSession = null;

  @override
  Future<ApiTokenResponse> login(ApiLoginRequest request) async {
    if (factory.rejectPassword || request.password != 'password') {
      throw const ApiException(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'invalid credentials',
      );
    }
    final id = request.email == 'b@example.test' ? _accountB : _accountA;
    factory.activeSession = factory.sessions[id];
    factory.loginDeviceNames.add(request.deviceName);
    return const ApiTokenResponse(
      accessToken: 'access',
      expiresIn: 900,
      refreshToken: 'refresh',
    );
  }

  @override
  Future<ApiSession?> getSession() async {
    if (factory.offline) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: 'offline',
      );
    }
    return factory.activeSession;
  }

  @override
  Uint8List createSecureCheckpoint(ApiSession session) =>
      Uint8List.fromList(session.userId.codeUnits);

  @override
  ApiSessionCheckpoint restoreSecureCheckpoint(Uint8List bytes) {
    final userId = String.fromCharCodes(bytes);
    final session = factory.sessions[userId];
    if (session == null) throw const FormatException('unknown user');
    factory.activeSession = session;
    return ApiSessionCheckpoint(userId: userId, email: session.email);
  }

  @override
  Future<void> logout() async => factory.activeSession = null;

  @override
  Future<void> logoutAll() async {
    factory.logoutAllCalls++;
    if (factory.rejectLogoutAll) {
      throw const ApiException(
        statusCode: 503,
        code: 'unavailable',
        message: 'unavailable',
      );
    }
    factory.activeSession = null;
  }

  @override
  Future<ApiPasskeyOptions> passkeyRequestOptions() async {
    if (factory.offline) {
      throw const ApiException(
        statusCode: null,
        code: 'network_error',
        message: 'offline',
      );
    }
    return const ApiPasskeyOptions(
      optionsJson: '{"challenge":"AQID","rpId":"gainer.markfort.xyz"}',
      state: 'state',
    );
  }

  @override
  Future<ApiTokenResponse> loginWithPasskey({
    required String credentialJson,
    required String state,
    String? deviceName,
  }) async {
    if (factory.rejectPassword) {
      throw const ApiException(
        statusCode: 401,
        code: 'invalid_passkey',
        message: 'invalid passkey',
      );
    }
    factory.activeSession = factory.sessions[_accountB];
    factory.loginDeviceNames.add(deviceName);
    return const ApiTokenResponse(
      accessToken: 'access',
      expiresIn: 900,
      refreshToken: 'refresh',
    );
  }
}

class _FakePasskeys implements PasskeyPlatform {
  bool cancel = false;
  int assertions = 0;

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
  }) async {
    assertions++;
    if (cancel) return null;
    return PlatformPasskeyAssertion(
      credentialId: Uint8List.fromList([1]),
      clientDataJson: Uint8List.fromList([2]),
      authenticatorData: Uint8List.fromList([3]),
      signature: Uint8List.fromList([4]),
      userHandle: Uint8List.fromList([5]),
    );
  }
}
