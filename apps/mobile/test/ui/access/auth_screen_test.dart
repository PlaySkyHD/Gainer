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

  @override
  Future<void> acceptInvitation(ApiAcceptInvitationRequest request) async {
    acceptedToken = request.token;
  }
}
