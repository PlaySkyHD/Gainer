import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_template.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
import 'package:gainer_mobile/ui/features/training/workout_summary_screen.dart';

import '../cardio/cardio_test_support.dart' hide testId;
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

void main() {
  late TrainingHarness training;
  late CardioHarness cardio;
  late String workoutId;

  setUp(() async {
    training = await TrainingHarness.create();
    cardio = await CardioHarness.create();
  });

  tearDown(() async {
    await cardio.dispose();
    await training.dispose();
  });

  Future<void> pumpSummary(
    WidgetTester tester, {
    CardioFeature? feature,
    double textScale = 1,
    CardioPreferenceValues? prefs,
  }) async {
    final workout = await tester.runAsync(
      () => training.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
        end: DateTime.utc(2026, 10, 17, 9),
        blocks: [
          WorkoutBlock(
            workoutExerciseId: 'block-bench',
            sourceExerciseId: 'bench',
            exerciseNameSnapshot: 'Bankdrücken',
            exerciseTypeSnapshot: ExerciseKind.strength,
            sets: const [LoggedSet(setId: 's1', weightKg: 20, repetitions: 6)],
          ),
        ],
      ),
    );
    workoutId = workout!.workoutId;
    if (prefs != null) {
      await tester.runAsync(() => cardio.repository.preferences.write(prefs));
    }
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        home: WorkoutSummaryScreen(
          repository: training.repository,
          workoutId: workoutId,
          cardio: feature,
        ),
      ),
    );
    await settle(tester);
  }

  final card = find.byKey(const ValueKey('cardio-offer-card'));

  GainerPillButton pill(WidgetTester tester, String key) =>
      tester.widget<GainerPillButton>(find.byKey(ValueKey(key)));

  testWidgets('zeigt Zielbereich und Gurtstatus mit den Standardwerten', (
    tester,
  ) async {
    await pumpSummary(tester, feature: cardio.feature);

    expect(card, findsOneWidget);
    expect(find.text('Cardio anhängen'), findsOneWidget);
    expect(find.text('Zielbereich 120–140 bpm'), findsOneWidget);
    expect(find.text('Starten'), findsOneWidget);
    expect(find.text('Anpassen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zeigt die zuletzt genutzte Vorlage', (tester) async {
    await pumpSummary(
      tester,
      feature: cardio.feature,
      prefs: const CardioPreferenceValues(
        maxHeartRate: 190,
        lastTemplateId: CardioTemplate.zone2Id,
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('cardio-offer-target')))
          .data,
      'Zone 2 – 30 min',
    );
    expect(pill(tester, 'cardio-offer-start').onPressed, isNotNull);
  });

  testWidgets('ohne Cardio-Anbindung fehlt die Karte', (tester) async {
    await pumpSummary(tester);
    expect(card, findsNothing);
  });

  testWidgets('ausgeschaltet: keine Karte', (tester) async {
    await pumpSummary(
      tester,
      feature: cardio.feature,
      prefs: const CardioPreferenceValues(offerAfterStrength: false),
    );
    expect(card, findsNothing);
    expect(find.text('Cardio anhängen'), findsNothing);
  });

  testWidgets('keine Karte, solange Cardio läuft', (tester) async {
    await tester.runAsync(
      () => cardio.controller.start(
        zone: const CardioTargetZone(lowBpm: 120, highBpm: 140),
      ),
    );
    await pumpSummary(tester, feature: cardio.feature);
    expect(card, findsNothing);
  });

  testWidgets('Starten startet mit den letzten Werten und öffnet Live', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      feature: cardio.feature,
      prefs: const CardioPreferenceValues(
        maxHeartRate: 190,
        lastTemplateId: CardioTemplate.zone2Id,
        warmupSeconds: 60,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cardio-offer-start')));
    await pumpUi(tester);

    final draft = cardio.controller.active!;
    expect(draft.templateName, 'Zone 2 – 30 min');
    expect(draft.warmupSeconds, 60);
    expect(cardio.platform.started.single.phases, hasLength(1));
    // Live-Ansicht ist offen: Phasenkarte sichtbar.
    expect(find.byKey(const ValueKey('cardio-phase-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Starten ohne Vorlage nutzt den letzten Zielbereich', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      feature: cardio.feature,
      prefs: const CardioPreferenceValues(lastZoneLow: 125, lastZoneHigh: 145),
    );
    await tester.tap(find.byKey(const ValueKey('cardio-offer-start')));
    await pumpUi(tester);

    final draft = cardio.controller.active!;
    expect(draft.phases, isEmpty);
    expect(draft.targetZone, const CardioTargetZone(lowBpm: 125, highBpm: 145));
    expect(find.text('125–145 bpm'), findsOneWidget);
  });

  testWidgets('Anpassen öffnet das Start-Sheet', (tester) async {
    await pumpSummary(tester, feature: cardio.feature);
    await tester.tap(find.byKey(const ValueKey('cardio-offer-adjust')));
    await pumpUi(tester);
    expect(find.text('Cardio starten'), findsOneWidget);
    expect(cardio.controller.isRunning, isFalse);
  });

  testWidgets('Zonenvorlage ohne Zonen: Starten gesperrt mit Erklärung', (
    tester,
  ) async {
    await pumpSummary(
      tester,
      feature: cardio.feature,
      prefs: const CardioPreferenceValues(
        lastTemplateId: CardioTemplate.norwegianId,
      ),
    );
    expect(pill(tester, 'cardio-offer-start').onPressed, isNull);
    expect(
      find.byKey(const ValueKey('cardio-offer-missing-zones')),
      findsOneWidget,
    );
  });

  testWidgets('ohne Gurt steht, dass kein Puls erfasst wird', (tester) async {
    cardio.platform.hasSensor = false;
    await pumpSummary(tester, feature: cardio.feature);
    expect(find.text('Kein Gurt – es wird kein Puls erfasst'), findsOneWidget);
  });

  testWidgets('Textgröße 2 ohne Überlauf', (tester) async {
    await pumpSummary(tester, feature: cardio.feature, textScale: 2);
    expect(card, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
