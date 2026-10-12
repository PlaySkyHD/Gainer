import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/app.dart';

void main() {
  testWidgets('missing API configuration shows a safe startup error', (
    tester,
  ) async {
    await tester.pumpWidget(const GainerMobileApp(configuration: null));
    expect(find.text('Gainer kann noch nicht starten'), findsOneWidget);
    expect(find.textContaining('GAINER_API_ORIGIN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits a compact large-text viewport in $brightness mode', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const GainerMobileApp(configuration: null));
      await tester.pumpAndSettle();

      expect(find.text('Gainer kann noch nicht starten'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final theme = CupertinoTheme.of(
        tester.element(find.text('Gainer kann noch nicht starten')),
      );
      expect(theme.brightness, brightness);
    });
  }
}
