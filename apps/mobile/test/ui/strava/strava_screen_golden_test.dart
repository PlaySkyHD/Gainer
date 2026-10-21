import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/strava/strava_screen.dart';

import '../cardio/cardio_test_support.dart';
import '../training/training_test_support.dart';
import 'strava_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('strava screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      phoneSize(tester);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          home: StravaScreen(
            service: FakeStravaService(stravaStatus()),
            online: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StravaScreen),
        matchesGoldenFile('goldens/strava_screen_${brightness.name}.png'),
      );
    }, tags: ['golden']);
  }
}
