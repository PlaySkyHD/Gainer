import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_averages_view.dart';

import 'nutrition_averages_test.dart' show seededRepository, today;

void main() {
  for (final variant in const [
    (name: 'light', brightness: Brightness.light, scale: 1.0, days: 7),
    (name: 'dark', brightness: Brightness.dark, scale: 1.0, days: 30),
    (name: 'light_scale2', brightness: Brightness.light, scale: 2.0, days: 7),
  ]) {
    testWidgets('nutrition averages ${variant.name}', (tester) async {
      tester.view.physicalSize = Size(390, variant.scale > 1 ? 1500 : 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = await seededRepository();
      final overview = await repository.readAverages(today);
      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(variant.brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              platformBrightness: variant.brightness,
              textScaler: TextScaler.linear(variant.scale),
            ),
            child: GainerDesign(child: child!),
          ),
          home: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GainerSheetFrame(
                child: NutritionAveragesSheet(
                  overview: overview,
                  initialDays: variant.days,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoPageScaffold),
        matchesGoldenFile('goldens/nutrition_averages_${variant.name}.png'),
      );
    }, tags: ['golden']);
  }
}
