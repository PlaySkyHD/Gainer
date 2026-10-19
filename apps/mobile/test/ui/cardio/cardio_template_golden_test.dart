import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_start_sheet.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_template_screens.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final (label, scale, brightness) in [
    ('light', 1.0, Brightness.light),
    ('dark', 1.0, Brightness.dark),
    ('light_scale2', 2.0, Brightness.light),
  ]) {
    testWidgets('Live-Ansicht mit Phase $label', (tester) async {
      phoneSize(tester, height: scale > 1 ? 1500 : 900);
      final t0 = DateTime.utc(2026, 10, 18, 10);
      final harness = await tester.runAsync(
        () => CardioHarness.create(now: t0),
      );
      addTearDown(() => tester.runAsync(harness!.dispose));
      await tester.runAsync(() async {
        await harness!.repository.preferences.write(
          const CardioPreferenceValues(maxHeartRate: 190),
        );
        await harness.controller.start(template: CardioTemplate.norwegian);
        final at = t0.add(const Duration(minutes: 10, seconds: 46));
        harness
          ..now = at
          ..platform.latestBpm = 148
          ..platform.latestAt = at;
        await harness.controller.poll();
      });
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: scale,
          home: CardioLiveScreen(feature: harness!.feature),
        ),
      );
      await pumpUi(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CardioLiveScreen),
        matchesGoldenFile('goldens/cardio_live_phase_$label.png'),
      );
    }, tags: ['golden']);
  }

  for (final (label, scale, brightness) in [
    ('light', 1.0, Brightness.light),
    ('light_scale2', 2.0, Brightness.light),
  ]) {
    testWidgets('Start-Sheet mit Vorlage $label', (tester) async {
      phoneSize(tester, height: scale > 1 ? 1500 : 1000);
      final harness = await tester.runAsync(CardioHarness.create);
      addTearDown(() => tester.runAsync(harness!.dispose));
      await tester.runAsync(
        () => harness!.repository.preferences.write(
          const CardioPreferenceValues(
            maxHeartRate: 190,
            lastTemplateId: CardioTemplate.norwegianId,
          ),
        ),
      );
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: scale,
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () =>
                      showCardioStartSheet(context, harness!.feature),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUi(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/cardio_start_template_$label.png'),
      );
    }, tags: ['golden']);

    testWidgets('Vorlageneditor $label', (tester) async {
      phoneSize(tester, height: scale > 1 ? 1700 : 1000);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: brightness,
          textScale: scale,
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () => showCardioTemplateEditor(
                    context,
                    template: CardioTemplate.norwegian.copyWith(
                      id: 'x',
                      name: '4×4 (Norwegisch) Kopie',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpUi(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/cardio_template_editor_$label.png'),
      );
    }, tags: ['golden']);
  }
}
