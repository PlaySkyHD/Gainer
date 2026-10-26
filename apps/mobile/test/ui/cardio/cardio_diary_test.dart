import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_detail_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_live_screen.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_start_sheet.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

/// 100 Werte, Ø 132 bpm, 78 % im Zielbereich 120–140.
List<int> diaryHeartRate() => [
  ...List.filled(76, 134),
  ...List.filled(2, 133),
  ...List.filled(11, 100),
  ...List.filled(11, 150),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late TrainingHarness training;
  late CardioHarness cardio;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    training = await TrainingHarness.create();
    cardio = await CardioHarness.create();
    activeWorkout = ActiveWorkoutController(training.repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await training.dispose();
    await cardio.dispose();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: TrainingHomeScreen(
          repository: training.repository,
          activeWorkout: activeWorkout,
          cardio: cardio.feature,
        ),
      ),
    );
    await pumpUi(tester);
  }

  Future<void> seedMixed(WidgetTester tester) => tester.runAsync(() async {
    await training.seedWorkout(
      title: 'Push',
      start: DateTime(2026, 10, 2, 7).toUtc(),
      end: DateTime(2026, 10, 2, 8).toUtc(),
    );
    await cardio.seedSession(
      start: DateTime(2026, 10, 18, 9).toUtc(),
      length: const Duration(minutes: 30),
      heartRate: diaryHeartRate(),
    );
    await training.seedWorkout(
      title: 'Legs 2',
      start: DateTime(2026, 10, 15, 18).toUtc(),
      end: DateTime(2026, 10, 15, 19).toUtc(),
    );
  });

  testWidgets('Cardio steht zwischen den Trainings und zählt im Monat', (
    tester,
  ) async {
    await seedMixed(tester);
    await pumpHome(tester);

    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(find.text('3 Trainings'), findsOneWidget);
    expect(find.text('Rad-Ergometer'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('Ø 132 bpm · 78 % in Zone'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.heart_fill), findsOneWidget);
    // Neueste zuerst: Cardio (18.), Legs 2 (15.), Push (2.).
    final cardioY = tester.getTopLeft(find.text('Rad-Ergometer')).dy;
    final legsY = tester.getTopLeft(find.text('Legs 2')).dy;
    final pushY = tester.getTopLeft(find.text('Push')).dy;
    expect(cardioY, lessThan(legsY));
    expect(legsY, lessThan(pushY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Zeile lässt fehlende Teile weg', (tester) async {
    await tester.runAsync(() async {
      await cardio.seedSession(
        start: DateTime(2026, 10, 18, 9).toUtc(),
        length: const Duration(minutes: 20),
        heartRate: List.filled(241, 0),
      );
      await cardio.seedSession(
        start: DateTime(2026, 10, 10, 9).toUtc(),
        length: const Duration(minutes: 20),
        heartRate: [for (var i = 0; i < 241; i++) 131 + i % 3],
        zone: null,
      );
    });
    await pumpHome(tester);

    expect(find.textContaining('in Zone'), findsNothing);
    expect(find.text('Ø 132 bpm'), findsOneWidget);
    expect(find.text('2 Trainings'), findsOneWidget);
  });

  testWidgets('Löschen außerhalb des Tagebuchs kommt sofort an', (
    tester,
  ) async {
    await seedMixed(tester);
    await pumpHome(tester);
    expect(find.text('Rad-Ergometer'), findsOneWidget);

    // Etwa in der Detailansicht, die über eine andere Route offen war.
    await tester.runAsync(() async {
      final session = (await cardio.repository.readSessions()).single;
      await cardio.repository.deleteSession(session.sessionId);
    });
    await pumpUi(tester);

    expect(find.text('Rad-Ergometer'), findsNothing);
  });

  testWidgets('eine per Sync gezogene Einheit erscheint nach dem Pull', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Rad-Ergometer'), findsNothing);

    // Der Pull schreibt am Repository vorbei in denselben Speicher.
    await tester.runAsync(() async {
      final other = CardioRepository(store: cardio.store);
      await other.saveFinished(
        CardioSession(
          sessionId: other.newSessionId(),
          startedAtUtc: DateTime(2026, 10, 18, 9).toUtc(),
          endedAtUtc: DateTime(2026, 10, 18, 9, 30).toUtc(),
          heartRateBpm: diaryHeartRate(),
          rrIntervalsMs: const [],
          createdAtUtc: DateTime(2026, 10, 18, 9, 30).toUtc(),
          updatedAtUtc: DateTime(2026, 10, 18, 9, 30).toUtc(),
        ),
      );
    });
    await pumpUi(tester);
    expect(find.text('Rad-Ergometer'), findsNothing);

    cardio.repository.notifyExternalChange();
    await pumpUi(tester);
    expect(find.text('Rad-Ergometer'), findsOneWidget);
  });

  testWidgets('eine über die Live Activity beendete Einheit erscheint', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Rad-Ergometer'), findsNothing);

    // Die Live-Ansicht wurde nicht aus dem Tagebuch geöffnet.
    await tester.runAsync(() async {
      await cardio.controller.start();
      cardio.now = cardio.now.add(const Duration(minutes: 20));
      await cardio.controller.finish();
    });
    await pumpUi(tester);

    expect(find.text('Rad-Ergometer'), findsOneWidget);
  });

  testWidgets('Tippen öffnet das Detail', (tester) async {
    await seedMixed(tester);
    await pumpHome(tester);

    await tester.tap(find.text('Rad-Ergometer'));
    await pumpUi(tester);

    expect(find.byType(CardioDetailScreen), findsOneWidget);
    expect(find.text('Kennzahlen'), findsOneWidget);
  });

  testWidgets('Wischen löscht erst nach Bestätigung', (tester) async {
    await seedMixed(tester);
    await pumpHome(tester);

    await tester.drag(find.text('Rad-Ergometer'), const Offset(-400, 0));
    await pumpUi(tester);
    expect(find.text('Einheit löschen?'), findsOneWidget);
    await tester.tap(inDialog('Abbrechen'));
    await pumpUi(tester);
    expect(find.text('Rad-Ergometer'), findsOneWidget);

    await tester.drag(find.text('Rad-Ergometer'), const Offset(-400, 0));
    await pumpUi(tester);
    await tester.tap(inDialog('Löschen'));
    await pumpUi(tester);

    expect(find.text('Rad-Ergometer'), findsNothing);
    expect(find.text('2 Trainings'), findsOneWidget);
    expect(await tester.runAsync(cardio.repository.readSessions), isEmpty);
  });

  testWidgets('Bearbeiten-Modus löscht Cardio per Minus', (tester) async {
    await seedMixed(tester);
    await pumpHome(tester);

    await tester.tap(find.text('Bearbeiten'));
    await pumpUi(tester);
    await tester.tap(find.bySemanticsLabel('Rad-Ergometer löschen'));
    await pumpUi(tester);
    await tester.tap(inDialog('Löschen'));
    await pumpUi(tester);

    expect(find.text('Rad-Ergometer'), findsNothing);
    expect(await tester.runAsync(cardio.repository.readSessions), isEmpty);
  });

  testWidgets('langes Drücken bietet Löschen', (tester) async {
    await seedMixed(tester);
    await pumpHome(tester);

    await tester.longPress(find.text('Rad-Ergometer'));
    await pumpUi(tester);
    expect(find.text('Löschen'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await pumpUi(tester);
    expect(find.text('Einheit löschen?'), findsOneWidget);
  });

  testWidgets('Herz-Button öffnet das Start-Sheet', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.bySemanticsLabel('Cardio starten'));
    await pumpUi(tester);

    expect(find.text('Cardio starten'), findsWidgets);
    expect(find.byKey(const ValueKey('cardio-start')), findsOneWidget);
    expect(find.byType(CardioLiveScreen), findsNothing);
  });

  testWidgets(
    'laufende Einheit: Karte und Herz-Button öffnen die Live-Ansicht',
    (tester) async {
      await tester.runAsync(() async {
        await cardio.controller.start();
        cardio.now = cardio.now.add(const Duration(minutes: 12, seconds: 34));
        cardio.platform.latestBpm = 131;
        cardio.platform.latestAt = cardio.now;
        await cardio.controller.poll();
      });
      await pumpHome(tester);

      expect(find.text('Cardio läuft · 12:34 · 131 bpm'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cardio-running-card')));
      await pumpUi(tester);
      expect(find.byType(CardioLiveScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(CardioLiveScreen))).pop();
      await pumpUi(tester);
      await pumpUi(tester);
      expect(find.byType(CardioLiveScreen), findsNothing);

      // Nur eine laufende Einheit: der Herz-Button öffnet die laufende.
      await tester.tap(find.bySemanticsLabel('Cardio starten'));
      await pumpUi(tester);
      expect(find.byType(CardioLiveScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('cardio-start')), findsNothing);
      expect(cardio.platform.started, hasLength(1));
    },
  );

  testWidgets('startOrOpenCardio startet nach dem Sheet die Live-Ansicht', (
    tester,
  ) async {
    phoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: CupertinoButton(
              onPressed: () => startOrOpenCardio(context, cardio.feature),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('cardio-start')));
    await pumpUi(tester);
    await pumpUi(tester);

    expect(cardio.controller.isRunning, isTrue);
    expect(find.byType(CardioLiveScreen), findsOneWidget);
  });
}
