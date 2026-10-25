import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/coach/coach_memory_screen.dart';

import 'coach_memory_fakes.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('coach memory screen matches golden in ${brightness.name}', (
      tester,
    ) async {
      await pumpCoachApp(
        tester,
        CoachMemoryScreen(
          repository: FakeCoachMemoryRepository(sampleMemories()),
        ),
        brightness: brightness,
      );

      await expectLater(
        find.byType(CoachMemoryScreen),
        matchesGoldenFile('goldens/coach_memory_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }

  testWidgets('coach memory editor matches golden', (tester) async {
    await pumpCoachApp(
      tester,
      CoachMemoryScreen(
        repository: FakeCoachMemoryRepository(sampleMemories()),
      ),
    );
    await tester.tap(find.text('Laktoseintoleranz'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/coach_memory_editor_light.png'),
    );
    expect(tester.takeException(), isNull);
  }, tags: ['golden']);
}
