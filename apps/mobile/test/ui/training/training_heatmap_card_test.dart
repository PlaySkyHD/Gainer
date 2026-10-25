import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/training/training_heatmap.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/training/training_format.dart';
import 'package:gainer_mobile/ui/features/training/training_heatmap_card.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_section.dart';
import 'package:gainer_mobile/ui/features/training/training_statistics_view_model.dart';

import '../calendar/calendar_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

LocalDay _oct(int day) => LocalDay(2026, 10, day);

const _gridKey = ValueKey('training-heatmap-grid');
const _selectionKey = ValueKey('training-heatmap-selection');
const _openKey = ValueKey('training-heatmap-open');
const _semanticsKey = ValueKey('training-heatmap-semantics');

/// Cardio, deren Einheiten nicht lesbar sind.
class _FailingCardio extends CardioRepository {
  _FailingCardio({required super.store});

  @override
  Future<List<CardioSession>> readSessions() async =>
      throw StateError('nicht lesbar');
}

/// Cardio, die mitzählt, wie oft die Einheiten gelesen werden.
class _CountingCardio extends CardioRepository {
  _CountingCardio({required super.store});

  var reads = 0;

  @override
  Future<List<CardioSession>> readSessions() {
    reads++;
    return super.readSessions();
  }
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
    // Der Fehler wird gemeldet, nicht verschluckt.
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('Tippen wählt einen Tag, erst die Schaltfläche öffnet ihn', (
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
    expect(find.byKey(_selectionKey), findsNothing);
    expect(find.byKey(_openKey), findsNothing);

    await tester.tapAt(_cellCenter(tester, _oct(12)));
    await tester.pump();
    // 45 Minuten Kraft plus 32 Minuten Cardio.
    expect(find.text('Mo, 12. Okt. · 77 min'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.byKey(_openKey));
    expect(opened, [_oct(12)]);
  });

  testWidgets('Textgröße 2 läuft nicht über', (tester) async {
    usePhoneSize(tester);
    final harness = await createCalendarHarness(tester);
    await tester.runAsync(() => _seed(harness));

    await _pumpSection(
      tester,
      harness,
      cardio: harness.cardio,
      textScale: 2,
      onOpenDay: (_) {},
    );
    await tester.tapAt(_cellCenter(tester, _oct(15)));
    await tester.pump();

    expect(
      find.text('3 Trainingstage in den letzten 12 Monaten'),
      findsOneWidget,
    );
    expect(find.text('Do, 15. Okt. · 32 min'), findsOneWidget);
    expect(find.text('Im Kalender öffnen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Auswahl', () {
    // Montag 5., 12. und Donnerstag 15. Oktober; heute ist Donnerstag, 22.
    TrainingHeatmap build({LocalDay? today}) => buildTrainingHeatmap(
      [
        for (final (day, minutes) in [(5, 60), (12, 45), (15, 30)])
          (
            startedAtUtc: DateTime.utc(2026, 10, day, 10),
            endedAtUtc: DateTime.utc(2026, 10, day, 10, minutes),
          ),
      ],
      today: today ?? calendarToday,
      dayOf: LocalDay.of,
    );

    Future<void> pumpCard(
      WidgetTester tester,
      TrainingHeatmap heatmap, {
      ValueChanged<LocalDay>? onOpenDay,
    }) async {
      await tester.pumpWidget(
        trainingTestApp(
          home: CupertinoPageScaffold(
            child: Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: Align(
                alignment: Alignment.topCenter,
                child: TrainingHeatmapCard(
                  heatmap: heatmap,
                  onOpenDay: onOpenDay,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Offset cellAt(WidgetTester tester, int week, int weekday) {
      final rect = tester.getRect(find.byKey(_gridKey));
      final step = rect.width / build().weeks.length;
      return rect.topLeft + Offset((week + 0.4) * step, (weekday + 0.4) * step);
    }

    String selection(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(_selectionKey)).data!;

    testWidgets('Tippen wählt auch Tage ohne Training und den nächsten Tag', (
      tester,
    ) async {
      usePhoneSize(tester);
      final heatmap = build();
      final opened = <LocalDay>[];
      await pumpCard(tester, heatmap, onOpenDay: opened.add);

      final thirteenth = heatmap.cellOf(_oct(13))!;
      await tester.tapAt(cellAt(tester, thirteenth.week, thirteenth.weekday));
      await tester.pump();
      expect(selection(tester), 'Di, 13. Okt. · kein Training');

      // Sonntag nach heute ist leer; nächstgelegen ist Sonntag, 18.
      final today = heatmap.cellOf(calendarToday)!;
      await tester.tapAt(cellAt(tester, today.week, 6));
      await tester.pump();
      expect(selection(tester), 'So, 18. Okt. · kein Training');

      await tester.tap(find.byKey(_openKey));
      expect(opened, [_oct(18)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ohne Kalender keine Schaltfläche', (tester) async {
      usePhoneSize(tester);
      final heatmap = build();
      await pumpCard(tester, heatmap);

      final cell = heatmap.cellOf(_oct(12))!;
      await tester.tapAt(cellAt(tester, cell.week, cell.weekday));
      await tester.pump();

      expect(selection(tester), 'Mo, 12. Okt. · 45 min');
      expect(find.byKey(_openKey), findsNothing);
    });

    testWidgets('VoiceOver springt von Trainingstag zu Trainingstag', (
      tester,
    ) async {
      usePhoneSize(tester);
      final semantics = tester.ensureSemantics();
      final opened = <LocalDay>[];
      await pumpCard(tester, build(), onOpenDay: opened.add);

      SemanticsNode node() => tester.getSemantics(find.byKey(_semanticsKey));
      void perform(SemanticsAction action) =>
          node().owner!.performAction(node().id, action);

      var data = node().getSemanticsData();
      expect(data.label, '3 Trainingstage in den letzten 12 Monaten');
      expect(data.value, 'Kein Tag gewählt');
      // Ohne Auswahl beginnen beide Richtungen beim jüngsten Trainingstag.
      expect(data.increasedValue, 'Do, 15. Okt. · 30 min');
      expect(data.decreasedValue, 'Do, 15. Okt. · 30 min');
      expect(find.bySemanticsLabel('Im Kalender öffnen'), findsNothing);

      perform(SemanticsAction.increase);
      await tester.pump();
      data = node().getSemanticsData();
      expect(data.value, 'Do, 15. Okt. · 30 min');
      expect(data.decreasedValue, 'Mo, 12. Okt. · 45 min');
      // Nach dem jüngsten Trainingstag gibt es keinen weiteren.
      expect(data.hasAction(SemanticsAction.increase), isFalse);

      perform(SemanticsAction.decrease);
      await tester.pump();
      expect(node().getSemanticsData().value, 'Mo, 12. Okt. · 45 min');

      perform(SemanticsAction.increase);
      await tester.pump();
      expect(node().getSemanticsData().value, 'Do, 15. Okt. · 30 min');

      // Die sichtbare Zeile wird nicht ein zweites Mal vorgelesen.
      expect(find.byKey(_selectionKey), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('15. Okt')), findsNothing);

      // Die Schaltfläche ist ein eigenes, erreichbares Element.
      final button = find.bySemanticsLabel('Im Kalender öffnen');
      expect(button, findsOneWidget);
      final buttonNode = tester.getSemantics(button);
      buttonNode.owner!.performAction(buttonNode.id, SemanticsAction.tap);
      expect(opened, [_oct(15)]);
      semantics.dispose();
    });

    testWidgets('die Auswahl bleibt beim Neuladen, solange der Tag passt', (
      tester,
    ) async {
      usePhoneSize(tester);
      final heatmap = build();
      await pumpCard(tester, heatmap);
      final cell = heatmap.cellOf(_oct(12))!;
      await tester.tapAt(cellAt(tester, cell.week, cell.weekday));
      await tester.pump();

      await pumpCard(tester, build());
      expect(selection(tester), 'Mo, 12. Okt. · 45 min');

      await pumpCard(tester, build(today: LocalDay(2027, 11, 1)));
      expect(find.byKey(_selectionKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
    final heatmap = trainingHeatmapOf(
      inputs.workouts,
      await harness.cardio.readSessions(),
      today: calendarToday,
    );

    expect(heatmap.trainingDays, 2);
    expect(heatmap.cellOf(_oct(8)), isNotNull);
    final cell = heatmap.cellOf(_oct(12))!;
    // 45 Minuten Kraft plus 32 Minuten Cardio.
    expect(heatmap.dayAt(cell.week, cell.weekday)!.minutes, 77);
    final eighth = heatmap.cellOf(_oct(8))!;
    expect(heatmap.dayAt(eighth.week, eighth.weekday)!.hasTraining, isFalse);
  });

  group('ViewModel', () {
    test('nicht lesbares Cardio meldet den Fehler und lässt nur die Heatmap '
        'weg', () async {
      final harness = await CalendarHarness.create();
      addTearDown(harness.dispose);
      await _seed(harness);
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final model = TrainingStatisticsViewModel(
        repository: harness.repository,
        cardio: _FailingCardio(store: harness.training.store),
      );
      addTearDown(model.dispose);

      await model.load();

      expect(model.heatmap, isNull);
      expect(model.exercises, isNotEmpty);
      expect(model.errorMessage, isNull);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
    });

    test('der Aufwärm-Schalter lädt Cardio und Heatmap nicht neu', () async {
      final harness = await CalendarHarness.create();
      addTearDown(harness.dispose);
      await _seed(harness);
      final cardio = _CountingCardio(store: harness.training.store);
      final model = TrainingStatisticsViewModel(
        repository: harness.repository,
        cardio: cardio,
      );
      addTearDown(model.dispose);

      await model.load();
      final heatmap = model.heatmap;
      expect(cardio.reads, 1);
      expect(heatmap!.trainingDays, 3);

      await model.setIncludeWarmups(true);

      expect(model.includeWarmups, isTrue);
      expect(model.exercises, isNotEmpty);
      expect(cardio.reads, 1);
      expect(model.heatmap, same(heatmap));
    });
  });

  test('trainingHeatmapOf übergeht gelöschte Cardio-Einheiten', () async {
    final harness = await CalendarHarness.create();
    addTearDown(harness.dispose);
    await _seed(harness);
    final inputs = await loadStatisticsInputs(harness.repository);
    final deleted = [
      for (final session in await harness.cardio.readSessions())
        session.copyWith(deletedAtUtc: () => DateTime.utc(2026, 10, 20)),
    ];

    final heatmap = trainingHeatmapOf(
      inputs.workouts,
      deleted,
      today: calendarToday,
    );

    // Nur noch Kraft am 5. und 12.; Cardio am 15. entfällt.
    expect(heatmap.trainingDays, 2);
    expect(heatmap.dayOn(_oct(15))!.hasTraining, isFalse);
  });

  test('Auswahlring bleibt in der halben Lücke und auf der Malfläche', () {
    for (final step in [6.0, 10.0, 16.0]) {
      final size = Size(step * 53, step * 7);
      final gap = math.max(1.0, step * 0.2);
      for (final (week, weekday) in [(0, 0), (10, 3), (52, 6)]) {
        final ring = trainingHeatmapSelectionRing(
          week: week,
          weekday: weekday,
          step: step,
          size: size,
        );
        // Außenkante des Strichs.
        final outer = ring.shape.outerRect.inflate(ring.stroke / 2);
        final allowed = Rect.fromLTWH(
          week * step - gap / 2,
          weekday * step - gap / 2,
          step,
          step,
        ).intersect(Offset.zero & size);
        const epsilon = 1e-9;
        expect(outer.left, greaterThanOrEqualTo(allowed.left - epsilon));
        expect(outer.top, greaterThanOrEqualTo(allowed.top - epsilon));
        expect(outer.right, lessThanOrEqualTo(allowed.right + epsilon));
        expect(outer.bottom, lessThanOrEqualTo(allowed.bottom + epsilon));
        expect(ring.shape.width, greaterThan(0));
      }
    }
  });

  test('Text eines gewählten Tags', () {
    final heatmap = buildTrainingHeatmap(
      [
        (
          startedAtUtc: DateTime.utc(2026, 10, 12, 10),
          endedAtUtc: DateTime.utc(2026, 10, 12, 10, 45),
        ),
      ],
      today: calendarToday,
      dayOf: LocalDay.of,
    );

    expect(
      trainingHeatmapDayText(heatmap.dayOn(_oct(12))!),
      'Mo, 12. Okt. · 45 min',
    );
    expect(
      trainingHeatmapDayText(heatmap.dayOn(_oct(13))!),
      'Di, 13. Okt. · kein Training',
    );
  });

  test('Monatsnamen kommen aus einem gemeinsamen Helfer', () {
    expect(
      [for (var m = 1; m <= 12; m++) formatMonthLabel(m)],
      [
        'Jan',
        'Feb',
        'Mär',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez',
      ],
    );
    expect(formatMonthShort(3), 'März');
    expect(formatMonthShort(9), 'Sept.');
    expect(formatShortDate(DateTime(2026, 10, 16)), '16. Okt.');
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
