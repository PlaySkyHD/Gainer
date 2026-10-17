import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_view_model.dart';

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
    expect(find.text('128.3 kg'), findsOneWidget);
    expect(find.text('70.0 kg'), findsOneWidget);
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
