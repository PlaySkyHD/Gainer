import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/data/services/platform/generated/mobile_platform_api.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/features/access/auth_screen.dart';

void main() {
  testWidgets(
    'invitation token entry validates empty input without a request',
    (tester) async {
      final controller = MobileAuthController(
        configuration: MobileAppConfiguration(
          api: Uri.parse('https://api.example.test'),
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        CupertinoApp(home: AuthScreen(controller: controller)),
      );
      await tester.tap(find.text('Einladung annehmen'));
      await tester.pumpAndSettle();
      expect(find.text('Einladungscode oder Einladungslink'), findsOneWidget);

      await tester.tap(find.text('Einladung bestätigen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gib einen gültigen Einladungscode oder Einladungslink ein.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('passkey button opens the system sheet for the domain', (
    tester,
  ) async {
    final passkeys = _CancellingPasskeys();
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
      ),
      apiFactory: _PasskeyOptionsApi.new,
      passkeys: passkeys,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(home: AuthScreen(controller: controller)),
    );
    await tester.tap(find.text('Mit Passkey anmelden'));
    await tester.pumpAndSettle();

    expect(passkeys.relyingParties, ['gainer.markfort.xyz']);
    expect(controller.state, isNot(MobileAuthState.signedIn));
    expect(controller.errorMessage, isNull);

    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Mit Passkey anmelden'), findsNothing);
  });

  testWidgets('invitation link extracts and submits only its token', (
    tester,
  ) async {
    _InviteApi? api;
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
      ),
      apiFactory: (configuration) => api = _InviteApi(configuration),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(home: AuthScreen(controller: controller)),
    );
    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).first,
      'https://app.example.test/accept-invitation?token=abc%2B123',
    );
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'new-password',
    );
    await tester.tap(find.text('Einladung bestätigen'));
    await tester.pumpAndSettle();

    expect(api?.acceptedToken, 'abc+123');
    expect(
      find.text(
        'Einladung angenommen. Melde dich jetzt mit deinem neuen Konto an.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a double tap on confirm sends the invitation only once', (
    tester,
  ) async {
    _InviteApi? api;
    final gate = Completer<void>();
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
      ),
      apiFactory: (configuration) =>
          api = _InviteApi(configuration)..gate = gate,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(home: AuthScreen(controller: controller)),
    );
    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'abc123');
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'new-password',
    );
    await tester.tap(find.text('Einladung bestätigen'));
    await tester.tap(find.text('Einladung bestätigen'), warnIfMissed: false);
    gate.complete();
    await tester.pumpAndSettle();

    expect(api?.acceptCalls, 1);
  });

  testWidgets('accepted invitation returns to sign-in with cleared secrets', (
    tester,
  ) async {
    _InviteApi? api;
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
      ),
      apiFactory: (configuration) => api = _InviteApi(configuration),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(home: AuthScreen(controller: controller)),
    );
    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).first, 'abc123');
    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'new-password',
    );
    await tester.tap(find.text('Einladung bestätigen'));
    await tester.pumpAndSettle();

    expect(find.text('Einladung bestätigen'), findsNothing);
    expect(find.text('Anmelden'), findsNWidgets(2));
    expect(find.text('E-Mail-Adresse'), findsOneWidget);
    expect(find.text('Mit Passkey anmelden'), findsOneWidget);
    expect(
      find.text(
        'Einladung angenommen. Melde dich jetzt mit deinem neuen Konto an.',
      ),
      findsOneWidget,
    );
    expect(find.text('new-password'), findsNothing);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
          .controller
          ?.text,
      isEmpty,
    );

    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).first)
          .controller
          ?.text,
      isEmpty,
    );
    expect(api?.acceptCalls, 1);
  });

  testWidgets('local invitation error wins over an old sign-in error', (
    tester,
  ) async {
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
      ),
      apiFactory: _InviteApi.new,
      secureSessions: _MemorySecureSession(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(home: AuthScreen(controller: controller)),
    );
    await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.test');
    await tester.enterText(find.byType(CupertinoTextField).last, 'wrong');
    await tester.tap(find.widgetWithText(CupertinoButton, 'Anmelden'));
    await tester.pumpAndSettle();
    expect(
      find.text('E-Mail-Adresse oder Passwort stimmen nicht.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Einladung annehmen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einladung bestätigen'));
    await tester.pumpAndSettle();

    const local = 'Gib einen gültigen Einladungscode oder Einladungslink ein.';
    expect(find.text(local), findsOneWidget);
    expect(
      find.text('E-Mail-Adresse oder Passwort stimmen nicht.'),
      findsNothing,
    );
  });
}

class _PasskeyOptionsApi extends ApiClient {
  _PasskeyOptionsApi(ApiConfiguration configuration)
    : super(configuration: configuration);

  @override
  Future<ApiPasskeyOptions> passkeyRequestOptions() async =>
      const ApiPasskeyOptions(
        optionsJson: '{"challenge":"AQID","rpId":"gainer.markfort.xyz"}',
        state: 'state',
      );
}

class _CancellingPasskeys implements PasskeyPlatform {
  final relyingParties = <String>[];

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
    relyingParties.add(relyingPartyId);
    return null;
  }
}

class _InviteApi extends ApiClient {
  _InviteApi(ApiConfiguration configuration)
    : super(configuration: configuration);

  String? acceptedToken;
  int acceptCalls = 0;
  Completer<void>? gate;

  @override
  Future<ApiTokenResponse> login(ApiLoginRequest request) async =>
      throw const ApiException(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'invalid',
      );

  @override
  Future<void> acceptInvitation(ApiAcceptInvitationRequest request) async {
    acceptCalls++;
    await gate?.future;
    acceptedToken = request.token;
  }
}

class _MemorySecureSession implements SecureSessionPlatform {
  @override
  Future<void> clearCheckpoint(String apiOrigin) async {}

  @override
  Future<Uint8List?> readCheckpoint(String apiOrigin) async => null;

  @override
  Future<void> writeCheckpoint(String apiOrigin, Uint8List checkpoint) async {}
}
