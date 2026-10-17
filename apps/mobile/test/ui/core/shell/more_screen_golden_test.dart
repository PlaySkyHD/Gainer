import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

import '../../../../integration_test/ui_design_test.dart'
    show createUiDesignFixture;

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('more menu matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await tester.runAsync(createUiDesignFixture);
      if (fixture == null) {
        throw StateError('Could not create the design fixture.');
      }
      addTearDown(() => tester.runAsync(fixture.dispose));

      await tester.pumpWidget(
        fixture.app(GainerTheme.forBrightness(brightness)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehr').last);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/more_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
