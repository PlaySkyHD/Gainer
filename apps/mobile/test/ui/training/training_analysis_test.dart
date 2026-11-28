import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/training_analysis_screen.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';

import 'training_analysis_test_support.dart';
import 'training_plans_test_support.dart' show usePhoneSize;
import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create(now: analysisNow);
  });

  tearDown(() => harness.dispose());

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1}) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: TrainingAnalysisScreen(repository: harness.repository),
      ),
    );
    await settle(tester);
  }

  Finder exerciseRow(String id) =>
      find.byKey(ValueKey('analysis-exercise-$id'));

  testWidgets('Statistik öffnet die Trainingsanalyse', (tester) async {
    await tester.runAsync(() => seedAnalysisScenario(harness));
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: TrainingStatisticsSection(repository: harness.repository),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('statistics-analysis')),
    );
    await tester.tap(find.byKey(const ValueKey('statistics-analysis')));
    await settle(tester);

    expect(find.byType(TrainingAnalysisScreen), findsOneWidget);
    expect(find.text('Trainingsanalyse'), findsWidgets);
  });

  testWidgets('Liste zeigt Status, Empfehlung und Ermüdung', (tester) async {
    await tester.runAsync(() => seedAnalysisScenario(harness));
    await pumpScreen(tester);

    expect(find.text('Erhöht'), findsOneWidget);
    expect(find.text('1 Übung mit Hinweisen'), findsOneWidget);
    await scrollIntoView(tester, exerciseRow(analysisBenchId));
    expect(
      find.descendant(
        of: exerciseRow(analysisBenchId),
        matching: find.text('Steigt'),
      ),
      findsOneWidget,
    );
    expect(find.text('Gewicht erhöhen'), findsOneWidget);
    expect(
      find.descendant(
        of: exerciseRow(analysisDeadliftId),
        matching: find.text('Sinkt'),
      ),
      findsOneWidget,
    );
    expect(find.text('Deload · Ermüdung'), findsOneWidget);
  });

  testWidgets('4 W rechnet nur die letzten vier Wochen', (tester) async {
    await tester.runAsync(() => seedAnalysisScenario(harness));
    await pumpScreen(tester);

    await tester.tap(find.text('4 W'));
    await settle(tester);

    await scrollIntoView(tester, exerciseRow(analysisBenchId));
    expect(
      find.descendant(
        of: exerciseRow(analysisBenchId),
        matching: find.text('Zu wenig Daten'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Detail zeigt Empfehlung, Trends und Signale', (tester) async {
    await tester.runAsync(() => seedAnalysisScenario(harness));
    await pumpScreen(tester);

    await scrollIntoView(tester, exerciseRow(analysisDeadliftId));
    await tester.tap(exerciseRow(analysisDeadliftId));
    await settle(tester);

    expect(find.byType(TrainingAnalysisExerciseScreen), findsOneWidget);
    expect(
      find.text(
        'Ermüdung oder Leistungsabfall: nächstes Mal 120 kg (−10 %) und nicht '
        'bis zum Muskelversagen.',
      ),
      findsOneWidget,
    );
    expect(find.text('−11,6 %'), findsOneWidget);
    await scrollIntoView(tester, find.text('Weniger Wiederholungen'));
    expect(find.text('Oft bis zum Muskelversagen'), findsOneWidget);
    expect(find.text('Volumen und Kraft sinken'), findsOneWidget);
  });

  testWidgets('ohne Trainings erscheint ein Hinweis', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Keine Trainings im Zeitraum'), findsOneWidget);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('Textgröße $scale läuft nicht über', (tester) async {
      await tester.runAsync(() => seedAnalysisScenario(harness));
      await pumpScreen(tester, textScale: scale);
      await scrollIntoView(tester, exerciseRow(analysisBenchId));
      expect(tester.takeException(), isNull);

      await tester.tap(exerciseRow(analysisBenchId));
      await settle(tester);
      await scrollIntoView(tester, find.text('Einheiten').last);
      expect(tester.takeException(), isNull);
    });
  }
}
