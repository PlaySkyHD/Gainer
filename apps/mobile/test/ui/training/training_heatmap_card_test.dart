import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/training/training_heatmap.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/training/training_heatmap_card.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_view_model.dart';

import '../calendar/calendar_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

LocalDay _oct(int day) => LocalDay(2026, 10, day);

const _gridKey = ValueKey('training-heatmap-grid');

/// Cardio, deren Einheiten nicht lesbar sind.
class _FailingCardio extends CardioRepository {
  _FailingCardio({required super.store});

  @override
  Future<List<CardioSession>> readSessions() async =>
      throw StateError('nicht lesbar');
}

/// Kraft am 5. und 12., Cardio am 12. und 15. Oktober: drei Trainingstage.
Future<void> _seed(CalendarHarness harness) async {
  await harness.finishedEmpty('Beine', _oct(5));
  await harness.finishedEmpty('Oberkörper', _oct(12));
  await harness.cardioOn(_oct(12));
  await harness.cardioOn(_oct(15));
}

Future<void> _pumpSection(
  WidgetTester tester,
  CalendarHarness harness, {
  CardioRepository? cardio,
  ValueChanged<LocalDay>? onOpenDay,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    trainingTestApp(
      textScale: textScale,
      home: CupertinoPageScaffold(
        child: SingleChildScrollView(
          child: TrainingStatisticsSection(
            repository: harness.repository,
            cardio: cardio,
            onOpenCalendarDay: onOpenDay,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// Mitte des Kästchens von [day] in der Heatmap bis [calendarToday].
Offset _cellCenter(WidgetTester tester, LocalDay day) {
  final geometry = buildTrainingHeatmap(const [], today: calendarToday);
  final rect = tester.getRect(find.byKey(_gridKey));
  final step = rect.width / geometry.weeks.length;
  final cell = geometry.cellOf(day)!;
  return rect.topLeft +
      Offset((cell.week + 0.4) * step, (cell.weekday + 0.4) * step);
}

void main() {
  testWidgets('Karte zählt Kraft und Cardio und nennt die Zusammenfassung', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));

    await _pumpSection(tester, harness, cardio: harness.cardio);

    const summary = '3 Trainingstage in den letzten 12 Monaten';
    expect(find.text('Trainingstage'), findsOneWidget);
    expect(find.text(summary), findsOneWidget);
    expect(find.bySemanticsLabel(summary), findsOneWidget);
    expect(find.text('Weniger'), findsOneWidget);
    expect(find.text('Mehr'), findsOneWidget);
    // 53 Wochen passen ohne Scrollen auf 390 pt.
    expect(find.byKey(const ValueKey('training-heatmap-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Cardio zählt nur Krafttraining', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));

    await _pumpSection(tester, harness);

    expect(
      find.text('2 Trainingstage in den letzten 12 Monaten'),
      findsOneWidget,
    );
  });

  testWidgets('ohne Training entfällt die Karte', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);

    await _pumpSection(tester, harness, cardio: harness.cardio);

    expect(find.byKey(const ValueKey('training-heatmap')), findsNothing);
    expect(find.text('Noch keine Statistik'), findsOneWidget);
  });

  testWidgets('nicht lesbare Cardio-Einheiten blenden nur die Karte aus', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));

    await _pumpSection(
      tester,
      harness,
      cardio: _FailingCardio(store: harness.training.store),
    );

    expect(find.byKey(const ValueKey('training-heatmap')), findsNothing);
    expect(find.text('Kreuzheben'), findsWidgets);
  });

  testWidgets('Tippen auf einen Trainingstag öffnet den Kalendertag', (
    tester,
  ) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));
    final opened = <LocalDay>[];

    await _pumpSection(
      tester,
      harness,
      cardio: harness.cardio,
      onOpenDay: opened.add,
    );
    await tester.tapAt(_cellCenter(tester, _oct(13)));
    await tester.tapAt(_cellCenter(tester, _oct(12)));
    await tester.tapAt(_cellCenter(tester, _oct(15)));

    expect(opened, [_oct(12), _oct(15)]);
  });

  testWidgets('Textgröße 2 läuft nicht über', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));

    await _pumpSection(tester, harness, cardio: harness.cardio, textScale: 2);

    expect(
      find.text('3 Trainingstage in den letzten 12 Monaten'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('Breite', () {
    final heatmap = buildTrainingHeatmap([
      (
        startedAtUtc: DateTime.utc(2026, 10, 20, 10),
        endedAtUtc: DateTime.utc(2026, 10, 20, 11),
      ),
    ], today: calendarToday);

    Future<void> pumpCard(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        trainingTestApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: TrainingHeatmapCard(heatmap: heatmap),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('schmal scrollt waagerecht und beginnt bei heute', (
      tester,
    ) async {
      usePhoneSize(tester);
      await pumpCard(tester, 260);

      expect(
        find.byKey(const ValueKey('training-heatmap-scroll')),
        findsOneWidget,
      );
      expect(find.text('1 Trainingstag in den letzten 12 Monaten'), findsOne);
      // Rechts endet das Raster bündig mit dem sichtbaren Bereich.
      final scroll = tester.getRect(
        find.byKey(const ValueKey('training-heatmap-scroll')),
      );
      expect(tester.getRect(find.byKey(_gridKey)).right, scroll.right);
      expect(tester.takeException(), isNull);
    });

    testWidgets('breit bleiben die Kästchen klein', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpCard(tester, 1100);

      expect(
        tester.getSize(find.byKey(_gridKey)).width,
        16.0 * heatmap.weeks.length,
      );
      expect(
        find.byKey(const ValueKey('training-heatmap-scroll')),
        findsNothing,
      );

      // Eine neue Breite zeichnet das Raster mit kleineren Kästchen neu.
      await pumpCard(tester, 400);
      expect(
        tester.getSize(find.byKey(_gridKey)).width,
        closeTo(400 - 2 * GainerSpacing.m, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('gelöschte Einheiten zählen nicht', () async {
    final harness = await CalendarHarness.create();
    addTearDown(harness.dispose);
    await _seed(harness);
    final deleted = await harness.training.seedWorkout(
      title: 'Gelöscht',
      start: DateTime.utc(2026, 10, 8, 10),
      end: DateTime.utc(2026, 10, 8, 11),
    );
    await harness.repository.deleteWorkout(deleted.workoutId);
    harness.resetClock();
    final sessions = await harness.cardio.readSessions();
    await harness.cardio.deleteSession(
      sessions
          .firstWhere((s) => localDayOfUtc(s.startedAtUtc) == _oct(15))
          .sessionId,
    );

    final inputs = await loadStatisticsInputs(harness.repository);
    final heatmap = await loadTrainingHeatmap(
      inputs.workouts,
      today: calendarToday,
      cardio: harness.cardio,
    );

    expect(heatmap.trainingDays, 2);
    expect(heatmap.cellOf(_oct(8)), isNotNull);
    final cell = heatmap.cellOf(_oct(12))!;
    // 45 Minuten Kraft plus 32 Minuten Cardio.
    expect(heatmap.dayAt(cell.week, cell.weekday)!.minutes, 77);
    final eighth = heatmap.cellOf(_oct(8))!;
    expect(heatmap.dayAt(eighth.week, eighth.weekday)!.hasTraining, isFalse);
  });

  test('Zusammenfassung und Farben', () {
    expect(
      trainingHeatmapSummary(142),
      '142 Trainingstage in den letzten 12 Monaten',
    );
    expect(
      trainingHeatmapSummary(1),
      '1 Trainingstag in den letzten 12 Monaten',
    );
    for (final colors in [GainerColors.light, GainerColors.dark]) {
      expect(trainingHeatmapColor(colors, 0), colors.elevatedSurface);
      expect(trainingHeatmapColor(colors, 4), colors.accent);
      expect(trainingHeatmapColor(colors, 9), colors.accent);
      expect(
        trainingHeatmapColor(colors, 1),
        isNot(trainingHeatmapColor(colors, 2)),
      );
    }
  });
}
