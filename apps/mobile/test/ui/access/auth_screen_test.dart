import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/ui/features/access/auth_screen.dart';

void main() {
  testWidgets(
    'invitation token entry validates empty input without a request',
    (tester) async {
      final controller = MobileAuthController(
        configuration: MobileAppConfiguration(
          api: Uri.parse('https://api.example.test'),
          trustedOrigin: Uri.parse('https://app.example.test'),
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

  testWidgets('invitation link extracts and submits only its token', (
    tester,
  ) async {
    _InviteApi? api;
    final controller = MobileAuthController(
      configuration: MobileAppConfiguration(
        api: Uri.parse('https://api.example.test'),
        trustedOrigin: Uri.parse('https://app.example.test'),
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

class _InviteApi extends ApiClient {
  _InviteApi(ApiConfiguration configuration)
    : super(configuration: configuration);

  String? acceptedToken;

  @override
  Future<void> acceptInvitation(ApiAcceptInvitationRequest request) async {
    acceptedToken = request.token;
  }
}
