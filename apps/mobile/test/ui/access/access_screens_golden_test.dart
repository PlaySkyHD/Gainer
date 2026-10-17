import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/auth/mobile_auth_controller.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/access/account_operator_screen.dart';
import 'package:gainer_mobile/ui/features/access/auth_screen.dart';

final _configuration = MobileAppConfiguration(
  api: Uri.parse('https://api.example.test'),
  trustedOrigin: Uri.parse('https://app.example.test'),
);

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('auth screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      _useCompactView(tester);
      final controller = MobileAuthController(configuration: _configuration);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(brightness),
          home: AuthScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AuthScreen),
        matchesGoldenFile('goldens/auth_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);

    testWidgets(
      'account operator screen matches golden in ${brightness.name} mode',
      (tester) async {
        _useCompactView(tester);
        // Ohne Anmeldung zeigt der Screen den Ladefehler mit allen Abschnitten.
        final controller = MobileAuthController(configuration: _configuration);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          CupertinoApp(
            debugShowCheckedModeBanner: false,
            theme: GainerTheme.forBrightness(brightness),
            home: AccountOperatorScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AccountOperatorScreen),
          matchesGoldenFile(
            'goldens/account_operator_screen_${brightness.name}.png',
          ),
        );
        expect(tester.takeException(), isNull);
      },
      tags: ['golden'],
    );
  }
}

void _useCompactView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
