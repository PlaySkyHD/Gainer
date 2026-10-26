import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_screen.dart';

import 'training_statistics_test_support.dart';
import 'training_test_support.dart';

const _bodyweightHint =
    'Für korrekte Werte fehlt ein Check-in mit Körpergewicht.';

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required String exerciseId,
    ExerciseStatisticsTab initialTab = ExerciseStatisticsTab.chart,
  }) async {
    await tester.pumpWidget(
      trainingTestApp(
        home: ExerciseStatisticsScreen(
          repository: harness.repository,
          exerciseId: exerciseId,
          initialTab: initialTab,
        ),
      ),
    );
    await settle(tester);
  }

  /// Wert in der Zeile mit dem Bezeichner, z. B. „10 Wdh.“. Die Suche bleibt in
  /// der Karte „Wiederholungsrekorde“, weil „8 Wdh.“ auch als Wert vorkommt.
  Finder valueInRepetitionRow(String label, String value) {
    final card = find
        .ancestor(
          of: find.text('Wiederholungsrekorde'),
          matching: find.byType(GainerCard),
        )
        .first;
    final row = find
        .ancestor(
          of: find.descendant(of: card, matching: find.text(label)),
          matching: find.byType(Row),
        )
        .first;
    return find.descendant(of: row, matching: find.text(value));
  }

  testWidgets('Rekorde zeigen Wiederholungsrekorde, fehlende als Strich', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSingleSquatSet(harness));

    await pumpScreen(
      tester,
      exerciseId: kneeExerciseId,
      initialTab: ExerciseStatisticsTab.records,
    );

    expect(find.text('Aktuelle Rekorde'), findsOneWidget);
    expect(valueInRepetitionRow('1 Wdh.', '100 kg'), findsOneWidget);
    expect(valueInRepetitionRow('3 Wdh.', '100 kg'), findsOneWidget);
    expect(valueInRepetitionRow('5 Wdh.', '100 kg'), findsOneWidget);
    expect(valueInRepetitionRow('8 Wdh.', '100 kg'), findsOneWidget);
    expect(valueInRepetitionRow('10 Wdh.', '–'), findsOneWidget);
    expect(valueInRepetitionRow('12 Wdh.', '–'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Graph zeigt den Verlauf und die Bestwerte', (tester) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSquatScenario(harness));

    await pumpScreen(tester, exerciseId: kneeExerciseId);

    expect(find.text('Max. 128,3 kg'), findsOneWidget);
    expect(find.text('Min. 126,7 kg'), findsOneWidget);
    expect(find.text('Für diesen Zeitraum gibt es keine Werte.'), findsNothing);
  });

  testWidgets('Verlauf listet frühere Trainings mit ihren Sätzen', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSquatScenario(harness));

    await pumpScreen(
      tester,
      exerciseId: kneeExerciseId,
      initialTab: ExerciseStatisticsTab.history,
    );

    expect(find.text('Beine B'), findsOneWidget);
    expect(find.text('Oberkörper'), findsOneWidget);
    expect(find.text('Beine A'), findsOneWidget);
    expect(find.text('Laufend'), findsNothing);
    expect(find.text('Gelöscht'), findsNothing);
    expect(find.text('Satz 1'), findsNWidgets(3));
  });

  testWidgets('Fehlendes Körpergewicht zeigt den Hinweis', (tester) async {
    _phoneSize(tester);
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push',
        start: DateTime(2026, 10, 15, 18).toUtc(),
        end: DateTime(2026, 10, 15, 19).toUtc(),
        blocks: [
          statBlock(
            exerciseId: pushupExerciseId,
            name: 'Liegestütz',
            kind: ExerciseKind.bodyweightOnly,
            sets: [statSet('p1', reps: 10)],
          ),
        ],
      ),
    );

    await pumpScreen(
      tester,
      exerciseId: pushupExerciseId,
      initialTab: ExerciseStatisticsTab.records,
    );

    expect(find.text(_bodyweightHint), findsOneWidget);
  });

  testWidgets('Schalter für Aufwärmsätze ändert den Verlauf', (tester) async {
    _phoneSize(tester);
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Schultern',
        start: DateTime(2026, 10, 2, 18).toUtc(),
        end: DateTime(2026, 10, 2, 19).toUtc(),
        blocks: [
          statBlock(
            exerciseId: pressExerciseId,
            name: 'Schulterdrücken',
            sets: [
              statSet('w', kg: 20, reps: 10, type: SetType.warmup),
              statSet('n', kg: 30, reps: 8),
            ],
          ),
        ],
      ),
    );

    await pumpScreen(
      tester,
      exerciseId: pressExerciseId,
      initialTab: ExerciseStatisticsTab.history,
    );
    expect(find.text('Satz 1'), findsOneWidget);
    expect(find.text('Satz 2'), findsNothing);

    await tester.tap(find.byType(CupertinoSwitch));
    await settle(tester);

    expect(find.text('Satz 2'), findsOneWidget);
    expect(find.text('Aufwärmen'), findsOneWidget);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('Verlauf, Graph und Rekorde laufen bei Textgröße $scale nicht '
        'über', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => seedSquatScenario(harness));

      await tester.pumpWidget(
        trainingTestApp(
          textScale: scale,
          home: ExerciseStatisticsScreen(
            repository: harness.repository,
            exerciseId: kneeExerciseId,
            initialTab: ExerciseStatisticsTab.history,
          ),
        ),
      );
      await settle(tester);
      for (final text in ['Satz 1', 'Beine A']) {
        await scrollIntoView(tester, find.text(text).last);
        expect(find.text(text).last, findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await scrollIntoView(tester, find.text('Rekorde'));
      await tester.tap(find.text('Rekorde'));
      await settle(tester);
      await scrollIntoView(tester, find.text('Rekordverlauf'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Gewichte erscheinen in der Kontoeinheit lbs mit Komma', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() async {
      await seedSquatScenario(harness);
      await TrainingPreferences(store: harness.repository.store)
          .update((current) => current.copyWith(weightUnit: WeightUnit.lbs));
    });

    await pumpScreen(
      tester,
      exerciseId: kneeExerciseId,
      initialTab: ExerciseStatisticsTab.history,
    );

    // 110 kg = 242,5 lbs; Volumen 1.100 kg = 2.425 lbs.
    expect(find.textContaining('242,5 lbs × 5'), findsWidgets);
    expect(find.textContaining('Max. 242,5 lbs'), findsWidgets);
    expect(find.textContaining('Volumen 2.425 lbs'), findsWidgets);
    expect(find.textContaining(' kg'), findsNothing);
  });

  testWidgets('openExerciseStatistics öffnet den gewünschten Tab', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSingleSquatSet(harness));

    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () => openExerciseStatistics(
                context,
                repository: harness.repository,
                exerciseId: kneeExerciseId,
                initialTab: ExerciseStatisticsTab.records,
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Öffnen'));
    await settle(tester);

    expect(find.text('Aktuelle Rekorde'), findsOneWidget);
    expect(find.text('Wiederholungsrekorde'), findsOneWidget);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
