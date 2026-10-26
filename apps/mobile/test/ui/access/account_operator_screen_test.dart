import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/pigeon_native_features_platform.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/access/account_operator_screen.dart';

const _operatorId = '10000000-0000-4000-8000-000000000001';
const _memberId = '20000000-0000-4000-8000-000000000002';
const _inviteLink = 'https://api.example.test/accept-invitation?token=abc123';

final _configuration = MobileAppConfiguration(
  api: Uri.parse('https://api.example.test'),
);

void main() {
  testWidgets('signed-out operator screen reports accounts as unavailable', (
    tester,
  ) async {
    _useTallView(tester);
    final controller = MobileAuthController(configuration: _configuration);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: AccountOperatorScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kontoverwaltung'), findsWidgets);
    expect(
      find.text(
        'Konten konnten nicht geladen werden. Prüfe deine Verbindung und Rolle.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.text('Liste aktualisieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account list shows status and never toggles the own account', (
    tester,
  ) async {
    _useTallView(tester);
    final directory = _OperatorDirectory();
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);

    expect(find.text('operator@example.test'), findsOneWidget);
    expect(find.text('member@example.test'), findsOneWidget);
    expect(find.text('Aktiv'), findsNWidgets(2));
    final switches = tester
        .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
        .toList();
    expect(switches, hasLength(2));
    expect(switches.first.onChanged, isNull);
    expect(switches.last.onChanged, isNotNull);

    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();

    expect(directory.statusChanges, [(_memberId, false)]);
    expect(find.text('Deaktiviert'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed status change keeps the account state and shows error', (
    tester,
  ) async {
    _useTallView(tester);
    final directory = _OperatorDirectory()..statusFails = true;
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();

    expect(
      find.text('Der Kontostatus konnte nicht geändert werden.'),
      findsOneWidget,
    );
    expect(directory.statusChanges, isEmpty);
    expect(find.text('Deaktiviert'), findsNothing);
    expect(find.text('Aktiv'), findsNWidgets(2));
  });

  testWidgets('invitation is issued for a trimmed address and copied', (
    tester,
  ) async {
    _useTallView(tester);
    final clipboard = _ClipboardRecorder()..install();
    addTearDown(clipboard.uninstall);
    final directory = _OperatorDirectory();
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.enterText(
      find.byType(CupertinoTextField),
      '  new.member@example.test  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(directory.invitationEmails, ['new.member@example.test']);
    expect(find.text(_inviteLink), findsOneWidget);
    expect(find.textContaining('Gültig bis'), findsOneWidget);
    expect(
      find.text('Diesen Link einmalig sicher an die Person weitergeben.'),
      findsOneWidget,
    );
    expect(directory.listCalls, 2);

    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pumpAndSettle();
    expect(clipboard.text, _inviteLink);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invitation button is disabled until the request completes', (
    tester,
  ) async {
    _useTallView(tester);
    final gate = Completer<void>();
    final directory = _OperatorDirectory()..createGate = gate;
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.enterText(
      find.byType(CupertinoTextField),
      'pending@example.test',
    );
    await tester.tap(find.text('Einladung erstellen'));
    await tester.pump();

    final pending = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, 'Einladung erstellen'),
    );
    expect(pending.onPressed, isNull);
    expect(find.text(_inviteLink), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    final ready = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, 'Einladung erstellen'),
    );
    expect(ready.onPressed, isNotNull);
    expect(find.text(_inviteLink), findsOneWidget);
  });

  testWidgets('a double tap issues only one invitation', (tester) async {
    _useTallView(tester);
    final gate = Completer<void>();
    final directory = _OperatorDirectory()..createGate = gate;
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.enterText(
      find.byType(CupertinoTextField),
      'double@example.test',
    );
    await tester.tap(find.text('Einladung erstellen'));
    await tester.tap(find.text('Einladung erstellen'), warnIfMissed: false);
    gate.complete();
    await tester.pumpAndSettle();

    expect(directory.invitationEmails, ['double@example.test']);
  });

  testWidgets('empty invitation address is rejected without a request', (
    tester,
  ) async {
    _useTallView(tester);
    final directory = _OperatorDirectory();
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.tap(find.text('Einladung erstellen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Gib die E-Mail-Adresse des neuen Kontos ein.'),
      findsOneWidget,
    );
    expect(directory.invitationEmails, isEmpty);
    expect(find.textContaining('accept-invitation'), findsNothing);
  });

  testWidgets('failed invitation keeps the address and shows a safe error', (
    tester,
  ) async {
    _useTallView(tester);
    final directory = _OperatorDirectory()..createFails = true;
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    await tester.enterText(
      find.byType(CupertinoTextField),
      'retry@example.test',
    );
    await tester.tap(find.text('Einladung erstellen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Die Einladung konnte nicht erstellt werden.'),
      findsOneWidget,
    );
    expect(find.textContaining('accept-invitation'), findsNothing);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .controller!
          .text,
      'retry@example.test',
    );
    expect(directory.invitationEmails, ['retry@example.test']);
  });

  testWidgets('failed account load can be retried from the refresh button', (
    tester,
  ) async {
    _useTallView(tester);
    final directory = _OperatorDirectory()..listFailures = 1;
    final controller = await _signedInOperator(tester, directory);

    await _pumpScreen(tester, controller);
    expect(
      find.text(
        'Konten konnten nicht geladen werden. Prüfe deine Verbindung und Rolle.',
      ),
      findsOneWidget,
    );
    expect(find.text('member@example.test'), findsNothing);

    await tester.tap(find.text('Liste aktualisieren'));
    await tester.pumpAndSettle();

    expect(directory.listCalls, 2);
    expect(find.text('member@example.test'), findsOneWidget);
    expect(
      find.text(
        'Konten konnten nicht geladen werden. Prüfe deine Verbindung und Rolle.',
      ),
      findsNothing,
    );
  });
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  MobileAuthController controller,
) async {
  await tester.pumpWidget(
    CupertinoApp(
      theme: GainerTheme.light,
      home: AccountOperatorScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<MobileAuthController> _signedInOperator(
  WidgetTester tester,
  _OperatorDirectory directory,
) async {
  final controller = MobileAuthController(
    configuration: _configuration,
    apiFactory: (configuration) => _OperatorApi(configuration, directory),
    secureSessions: _MemorySecureSession(),
    nativeFeatures: _QuietNativeFeatures(),
    accountDatabaseFactory: (_) async => LocalDatabase(NativeDatabase.memory()),
    installationDatabaseFactory: () async =>
        LocalDatabase(NativeDatabase.memory()),
  );
  addTearDown(controller.dispose);
  // Inactive (unlike paused) keeps frames running but stops the foreground
  // sync scheduler from starting a sync with network requests in this test.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await controller.initialize();
  await controller.login('operator@example.test', 'password');
  expect(controller.state, MobileAuthState.signedIn);
  expect(controller.account?.session.isAccountOperator, isTrue);
  return controller;
}

class _OperatorDirectory {
  final List<ApiAccountSummary> accounts = [
    const ApiAccountSummary(
      accountId: _operatorId,
      email: 'operator@example.test',
      isActive: true,
    ),
    const ApiAccountSummary(
      accountId: _memberId,
      email: 'member@example.test',
      isActive: true,
    ),
  ];
  final invitationEmails = <String>[];
  final statusChanges = <(String, bool)>[];
  int listCalls = 0;
  int listFailures = 0;
  bool createFails = false;
  bool statusFails = false;
  Completer<void>? createGate;
}

class _OperatorApi extends ApiClient {
  _OperatorApi(ApiConfiguration configuration, this.directory)
    : super(configuration: configuration);

  final _OperatorDirectory directory;

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
    userId: _operatorId,
    email: 'operator@example.test',
    isAccountOperator: true,
  );

  @override
  Uint8List createSecureCheckpoint(ApiSession session) =>
      Uint8List.fromList(session.userId.codeUnits);

  @override
  Future<void> logout() async {}

  @override
  Future<List<ApiAccountSummary>> listAccounts() async {
    directory.listCalls++;
    if (directory.listFailures > 0) {
      directory.listFailures--;
      throw const ApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'failed',
      );
    }
    return List.unmodifiable(directory.accounts);
  }

  @override
  Future<ApiInvitation> createInvitation(String email) async {
    directory.invitationEmails.add(email);
    await directory.createGate?.future;
    if (directory.createFails) {
      throw const ApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'failed',
      );
    }
    return ApiInvitation(
      activationPath: '/accept-invitation?token=abc123',
      expiresAt: DateTime.utc(2026, 10, 20, 12),
    );
  }

  @override
  Future<void> setAccountStatus(String accountId, bool isActive) async {
    if (directory.statusFails) {
      throw const ApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'failed',
      );
    }
    directory.statusChanges.add((accountId, isActive));
    final index = directory.accounts.indexWhere(
      (account) => account.accountId == accountId,
    );
    final current = directory.accounts[index];
    directory.accounts[index] = ApiAccountSummary(
      accountId: current.accountId,
      email: current.email,
      isActive: isActive,
    );
  }
}

class _ClipboardRecorder {
  String? text;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            text = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
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
