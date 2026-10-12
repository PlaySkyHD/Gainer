import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/app.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shell exposes accessible destinations and switches areas', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<MobileShellViewModel>(
        create: (_) => MobileShellViewModel(),
        child: const GainerMobileApp(),
      ),
    );

    expect(find.byKey(const ValueKey<String>('area-title')), findsOneWidget);
    expect(find.text('Training'), findsWidgets);
    expect(find.text('Dieser Bereich wird vorbereitet.'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    final trainingTab = find.bySemanticsLabel('Training').last;
    expect(
      tester.getSemantics(trainingTab).flagsCollection.isSelected.toString(),
      endsWith('.isTrue'),
    );
    semantics.dispose();

    await tester.tap(find.text('Ernährung').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('area-title')))
          .data,
      'Ernährung',
    );
    expect(find.text('Körper'), findsWidgets);
    expect(find.text('Fortschritt'), findsWidgets);
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

      await tester.pumpWidget(
        ChangeNotifierProvider<MobileShellViewModel>(
          create: (_) => MobileShellViewModel(),
          child: const GainerMobileApp(),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(
        find.byKey(const ValueKey<String>('area-title')),
      );
      expect(title.data, 'Training');
      expect(tester.takeException(), isNull);
      final theme = CupertinoTheme.of(
        tester.element(find.byKey(const ValueKey<String>('area-title'))),
      );
      expect(theme.brightness, brightness);
    });
  }
}
