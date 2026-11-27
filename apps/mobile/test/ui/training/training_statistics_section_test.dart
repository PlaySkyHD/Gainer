import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_view_model.dart';
import 'package:gainer_mobile/ui/features/training/training_trend_tiles.dart';

import 'training_statistics_test_support.dart';
import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;

  setUp(() async {
    harness = await TrainingHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> pumpSection(WidgetTester tester) async {
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
  }

  testWidgets('Liste zeigt nur trainierte Übungen mit aktuellem Rekord', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSquatScenario(harness));

    await pumpSection(tester);

    expect(find.text('Kniebeuge'), findsOneWidget);
    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Geheimübung'), findsNothing);
    expect(find.text('1RM 128,3 kg'), findsOneWidget);
    expect(find.text('1RM 70 kg'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Kniebeuge')).dy,
      lessThan(tester.getTopLeft(find.text('Bankdrücken')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Suche filtert die Übungsliste nach Namen', (tester) async {
    _phoneSize(tester);
    await tester.runAsync(() => seedSquatScenario(harness));

    await pumpSection(tester);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'bank');
    await settle(tester);

    expect(find.text('Bankdrücken'), findsOneWidget);
    expect(find.text('Kniebeuge'), findsNothing);
  });

  testWidgets('Leerer Zustand ohne beendete Trainings', (tester) async {
    _phoneSize(tester);
    await pumpSection(tester);

    expect(find.text('Noch keine Statistik'), findsOneWidget);
    expect(find.byType(CupertinoSearchTextField), findsNothing);
  });

  testWidgets('Verlauf zeigt Kennzahlen des Zeitraums und wechselt ihn', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(() async {
      await seedSquatScenario(harness);
      await saveWeightCheckIn(harness, localDate: '2026-10-10', weightKg: 81.5);
    });
    // seedWorkout stellt die Uhr auf den letzten Start; heute ist Samstag.
    harness.now = DateTime.utc(2026, 10, 17, 9);

    await pumpSection(tester);

    expect(find.text('Verlauf'), findsOneWidget);
    // Drei beendete Trainings à 60 min; gelöschte und laufende zählen nicht.
    expect(find.text('Ø 0,2 pro Woche'), findsOneWidget);
    expect(find.text('Ø 60 min'), findsOneWidget);
    expect(find.text('3 h'), findsOneWidget);
    expect(find.text('3.550 kg'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('Ø 6,3'), findsOneWidget);
    expect(find.text('81,5 kg'), findsOneWidget);

    await tester.ensureVisible(find.text('4 W'));
    await tester.tap(find.text('4 W'));
    await settle(tester);

    // 21. September bis 17. Oktober: 27 Tage, 3 Trainings.
    expect(find.text('Ø 0,8 pro Woche'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ohne Training und Check-in fehlt der Verlauf', (tester) async {
    _phoneSize(tester);
    await pumpSection(tester);

    expect(find.text('Verlauf'), findsNothing);
  });

  for (final scale in [1.4, 2.0]) {
    testWidgets('Verlauf läuft bei Textgröße $scale nicht über', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.runAsync(() => seedSquatScenario(harness));
      await tester.pumpWidget(
        trainingTestApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: CupertinoPageScaffold(
              child: SingleChildScrollView(
                child: TrainingStatisticsSection(
                  repository: harness.repository,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      final stacked = scale >= TrainingTrendTiles.stackScale;
      final trainings = tester.getRect(
        find.byKey(const ValueKey('trend-workoutsPerWeek')),
      );
      final duration = tester.getRect(
        find.byKey(const ValueKey('trend-averageDuration')),
      );
      expect(duration.top > trainings.top, stacked);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Aufwärmsätze-Schalter nimmt Übungen mit nur Aufwärmsätzen auf', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Schultern',
        start: DateTime(2026, 10, 2, 18).toUtc(),
        end: DateTime(2026, 10, 2, 19).toUtc(),
        blocks: [
          statBlock(
            exerciseId: 'stat-src-warm',
            name: 'Aufwärmübung',
            sets: [statSet('w', kg: 20, reps: 10, type: SetType.warmup)],
          ),
        ],
      ),
    );

    await pumpSection(tester);
    expect(find.text('Aufwärmübung'), findsNothing);
    expect(find.text('Noch keine Statistik'), findsOneWidget);

    await tester.ensureVisible(find.byType(CupertinoSwitch));
    await tester.tap(find.byType(CupertinoSwitch));
    await settle(tester);

    expect(find.text('Aufwärmübung'), findsOneWidget);
    expect(
      await tester.runAsync(() => readIncludeWarmupSets(harness.store)),
      isTrue,
    );
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
