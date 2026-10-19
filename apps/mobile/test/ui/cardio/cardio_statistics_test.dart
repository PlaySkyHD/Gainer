import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_statistics_area.dart';

import '../training/training_test_support.dart';
import 'cardio_test_support.dart';

/// Mittwoch, 21.10.2026, lokal.
final _now = DateTime(2026, 10, 21, 12);

/// Pulsreihe: [inZoneMinutes] bei [bpm] (Zielbereich 120–140), Rest darunter.
List<int> _series(int lengthMinutes, int inZoneMinutes, {int bpm = 130}) => [
  for (var i = 0; i < lengthMinutes * 12 + 1; i++)
    i < inZoneMinutes * 12 ? bpm : 100,
];

void main() {
  late CardioHarness harness;

  setUp(() async {
    harness = await CardioHarness.create();
  });

  tearDown(() async => harness.dispose());

  Future<void> seed(
    WidgetTester tester, {
    required DateTime start,
    int length = 30,
    int? inZone,
    int bpm = 130,
    double? power,
    (int, int)? recovery,
  }) async {
    await tester.runAsync(() async {
      final session = await harness.seedSession(
        start: start.toUtc(),
        length: Duration(minutes: length),
        heartRate: _series(length, inZone ?? length, bpm: bpm),
      );
      if (power != null) {
        await harness.repository.updateDetails(
          session.sessionId,
          averagePowerWatts: power,
        );
      }
      if (recovery != null) {
        await harness.repository.saveRecovery(
          session.sessionId,
          startBpm: recovery.$1,
          endBpm: recovery.$2,
        );
      }
    });
  }

  Future<void> openArea(
    WidgetTester tester, {
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    phoneSize(tester, height: 1100);
    await tester.pumpWidget(
      trainingTestApp(
        textScale: textScale,
        brightness: brightness,
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CardioStatisticsArea(
                repository: harness.repository,
                clock: () => _now,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('ohne Cardio steht ein Hinweis zum Starten statt Balken', (
    tester,
  ) async {
    await openArea(tester);
    expect(find.byKey(const ValueKey('cardio-stats-empty')), findsOneWidget);
    expect(find.text('Noch kein Cardio'), findsOneWidget);
    expect(find.byKey(const ValueKey('cardio-stats-weeks')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Spec: Diese Woche 95 / 150 min · 3 Einheiten · 1:42 h', (
    tester,
  ) async {
    await seed(
      tester,
      start: DateTime(2026, 10, 19, 8),
      length: 32,
      inZone: 30,
    );
    await seed(
      tester,
      start: DateTime(2026, 10, 20, 8),
      length: 38,
      inZone: 35,
    );
    await seed(
      tester,
      start: DateTime(2026, 10, 21, 8),
      length: 32,
      inZone: 30,
    );
    await openArea(tester);

    expect(find.text('Diese Woche 95 / 150 min'), findsOneWidget);
    expect(
      find.text('3 Einheiten · 1:42 h · Minuten im Zielbereich'),
      findsOneWidget,
    );
    // Ohne Zonen gibt es den Umschalter nicht.
    expect(find.text('Zone 2'), findsNothing);
    // Ohne Leistung: Hinweis und kein Verlauf.
    expect(
      find.text(
        'Trage die Ø-Leistung vom Ergometer ein, um deine Form zu sehen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ø Erholung', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wochenziel aus den Einstellungen', (tester) async {
    await seed(tester, start: DateTime(2026, 10, 20, 8), length: 30);
    await tester.runAsync(
      () => harness.repository.preferences.update(
        (current) => current.copyWith(weeklyTargetMinutes: 200),
      ),
    );
    await openArea(tester);
    expect(find.text('Diese Woche 30 / 200 min'), findsOneWidget);
  });

  testWidgets('Umschalter Zielbereich / Zone 2 mit konfigurierten Zonen', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 180),
      ),
    );
    // Zone 2 bei HFmax 180: 108 bis 126.
    await seed(tester, start: DateTime(2026, 10, 20, 8), length: 40, bpm: 115);
    await seed(tester, start: DateTime(2026, 10, 21, 8), length: 30, bpm: 130);
    await openArea(tester);

    expect(find.text('Zielbereich'), findsOneWidget);
    expect(find.text('Zone 2'), findsOneWidget);
    expect(find.text('Diese Woche 30 / 150 min'), findsOneWidget);
    await tester.tap(find.text('Zone 2'));
    await settle(tester);
    expect(find.text('Diese Woche 40 / 150 min'), findsOneWidget);
    expect(find.textContaining('Minuten in Zone 2'), findsOneWidget);
  });

  testWidgets('Spec: bei 150 W: 138 → 131 bpm und Form-Verlauf', (
    tester,
  ) async {
    for (final (day, power, bpm) in [
      (5, 148.0, 138),
      (9, 152.0, 136),
      (14, 150.0, 133),
      (20, 151.0, 131),
    ]) {
      await seed(
        tester,
        start: DateTime(2026, 10, day, 8),
        length: 30,
        bpm: bpm,
        power: power,
      );
    }
    await openArea(tester);

    expect(find.text('bei 150 W: 138 → 131 bpm'), findsOneWidget);
    expect(find.byKey(const ValueKey('cardio-stats-power-hint')), findsNothing);
    expect(find.text('Aerobe Form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ø Erholung der letzten 5 Einheiten', (tester) async {
    for (final day in [6, 8, 12, 15, 20]) {
      await seed(
        tester,
        start: DateTime(2026, 10, day, 8),
        recovery: (150, 124),
      );
    }
    await openArea(tester);
    expect(find.text('Ø Erholung −26 bpm (letzte 5)'), findsOneWidget);
  });

  testWidgets('Textgröße 2 läuft nicht über', (tester) async {
    await tester.runAsync(
      () => harness.repository.preferences.write(
        const CardioPreferenceValues(maxHeartRate: 180),
      ),
    );
    for (final (day, power, bpm) in [
      (5, 148.0, 138),
      (9, 152.0, 136),
      (14, 150.0, 133),
      (20, 151.0, 131),
    ]) {
      await seed(
        tester,
        start: DateTime(2026, 10, day, 8),
        bpm: bpm,
        power: power,
        recovery: (150, 124),
      );
    }
    await openArea(tester, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
