import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_nutrition_overview.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_view_model.dart';

import '../training/training_plans_test_support.dart';
import '../training/training_test_support.dart';
import 'calendar_test_support.dart';

const _target = CalendarNutritionTarget(
  kilocalories: 2724,
  proteinGrams: 180,
  carbohydrateGrams: 332,
  fatGrams: 80,
);

const _underTarget = CalendarNutrition(
  kilocalories: 1240,
  proteinGrams: 82,
  carbohydrateGrams: 120,
  fatGrams: 41.6,
  saltGrams: 3.44,
  target: _target,
);

/// Einzelne Karte auf Seitenhintergrund, wie in der Tagesansicht eingerückt.
Future<int> _pumpCard(
  WidgetTester tester,
  CalendarNutrition nutrition, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  var taps = 0;
  await tester.pumpWidget(
    trainingTestApp(
      brightness: brightness,
      textScale: textScale,
      home: Builder(
        builder: (context) => ColoredBox(
          color: GainerDesign.colorsOf(context).background,
          child: Padding(
            padding: const EdgeInsets.all(GainerSpacing.m),
            child: Column(
              children: [
                CalendarNutritionOverview(
                  nutrition: nutrition,
                  onTap: () => taps++,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return taps;
}

String _label(WidgetTester tester) => tester
    .getSemantics(find.byType(CalendarNutritionOverview))
    .getSemanticsData()
    .label;

String _centre(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('calendar-nutrition-centre')))
    .data!;

void main() {
  testWidgets('today without food shows the full target as remaining', (
    tester,
  ) async {
    await _pumpCard(tester, const CalendarNutrition.empty(_target));

    expect(_centre(tester), '2.724');
    expect(find.text('Übrig'), findsOneWidget);
    expect(find.text('Gegessen'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Ziel'), findsOneWidget);
    expect(find.text('0 / 332 g'), findsOneWidget);
    expect(find.text('0 / 180 g'), findsOneWidget);
    expect(find.text('0 / 80 g'), findsOneWidget);
    expect(find.text('0 / 6 g'), findsOneWidget);
    expect(find.byType(GainerProgressBar), findsNWidgets(4));
    expect(
      _label(tester),
      'Ernährung: 0 kcal gegessen, 2.724 kcal übrig, Ziel 2.724 kcal, '
      'Kohlenhydrate 0 von 332 g, Eiweiß 0 von 180 g, Fett 0 von 80 g, '
      'Salz 0 von 6 g',
    );
  });

  testWidgets('a logged day under target shows eaten, remaining and macros', (
    tester,
  ) async {
    await _pumpCard(tester, _underTarget);

    expect(_centre(tester), '1.484');
    expect(find.text('Übrig'), findsOneWidget);
    expect(find.text('1.240'), findsOneWidget);
    expect(find.text('2.724'), findsOneWidget);
    expect(find.text('120 / 332 g'), findsOneWidget);
    expect(find.text('82 / 180 g'), findsOneWidget);
    expect(find.text('42 / 80 g'), findsOneWidget);
    expect(find.text('3,4 / 6 g'), findsOneWidget);
    expect(find.text('Verbrannt'), findsNothing);
    expect(
      _label(tester),
      'Ernährung: 1.240 kcal gegessen, 1.484 kcal übrig, Ziel 2.724 kcal, '
      'Kohlenhydrate 120 von 332 g, Eiweiß 82 von 180 g, Fett 42 von 80 g, '
      'Salz 3,4 von 6 g',
    );
  });

  testWidgets('over target shows the excess as „Über“ in warning colour', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      const CalendarNutrition(
        kilocalories: 3000,
        proteinGrams: 200,
        carbohydrateGrams: 340,
        fatGrams: 95,
        target: _target,
      ),
    );

    expect(_centre(tester), '276');
    final over = tester.widget<Text>(find.text('Über'));
    expect(over.style!.color, GainerColors.light.warning);
    expect(find.text('Übrig'), findsNothing);
    expect(_label(tester), contains('3.000 kcal gegessen, 276 kcal über'));
  });

  testWidgets('without a target only „Gegessen“ and the plain macros show', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      const CalendarNutrition(
        kilocalories: 1240,
        proteinGrams: 82,
        carbohydrateGrams: 120,
      ),
    );

    expect(_centre(tester), '1.240');
    expect(find.text('Gegessen'), findsOneWidget);
    expect(find.text('Übrig'), findsNothing);
    expect(find.text('Ziel'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-nutrition-eaten')),
      findsNothing,
    );
    expect(find.text('120 g'), findsOneWidget);
    expect(find.text('82 g'), findsOneWidget);
    // Fett und Salz ohne Angabe.
    expect(find.text('– g'), findsNWidgets(2));
    expect(find.byType(GainerProgressBar), findsNothing);
    expect(
      _label(tester),
      'Ernährung: 1.240 kcal gegessen, Kohlenhydrate 120 g, Eiweiß 82 g, '
      'Fett ohne Angabe, Salz ohne Angabe',
    );
  });

  testWidgets('text size 2 stacks the figures and macros without overflow', (
    tester,
  ) async {
    usePhoneSize(tester);
    await _pumpCard(tester, _underTarget, textScale: 2);

    expect(tester.takeException(), isNull);
    final ring = tester.getRect(
      find.byKey(const ValueKey('calendar-nutrition-ring')),
    );
    final eaten = tester.getRect(
      find.byKey(const ValueKey('calendar-nutrition-eaten')),
    );
    final carbs = tester.getRect(
      find.byKey(const ValueKey('calendar-nutrition-carbs')),
    );
    final protein = tester.getRect(
      find.byKey(const ValueKey('calendar-nutrition-protein')),
    );
    expect(eaten.top, greaterThanOrEqualTo(ring.bottom));
    expect(protein.top, greaterThanOrEqualTo(carbs.bottom));
  });

  testWidgets('tapping the card opens the nutrition day', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      trainingTestApp(
        home: CalendarNutritionOverview(
          nutrition: _underTarget,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-nutrition-ring')));
    await tester.pump();
    expect(taps, 1);
  });

  group('day view', () {
    testWidgets('today shows the overview with its target before any food', (
      tester,
    ) async {
      usePhoneSize(tester);
      final harness = await createCalendarHarness(tester);
      await tester.runAsync(() => harness.target(from: '2026-10-01'));
      final days = <String>[];
      await pumpCalendar(tester, harness, onOpenNutritionDay: days.add);

      final card = find.byKey(const ValueKey('calendar-nutrition-card'));
      await scrollIntoView(tester, card);
      expect(_centre(tester), '2.600');
      expect(find.text('Übrig'), findsOneWidget);

      await tester.tap(card);
      await settle(tester);
      expect(days, ['2026-10-22']);
    });

    testWidgets('past days without food and future days show no overview', (
      tester,
    ) async {
      usePhoneSize(tester);
      final harness = await createCalendarHarness(tester);
      await tester.runAsync(() async {
        await harness.target(from: '2026-10-01');
        await harness.food(LocalDay(2026, 10, 14), kcal: 2350, protein: 142);
      });
      await pumpCalendar(tester, harness);

      await tapDay(tester, LocalDay(2026, 10, 13));
      expect(find.byType(CalendarNutritionOverview), findsNothing);
      await tapDay(tester, LocalDay(2026, 10, 23));
      expect(find.byType(CalendarNutritionOverview), findsNothing);
      await tapDay(tester, LocalDay(2026, 10, 14));
      expect(find.byType(CalendarNutritionOverview), findsOneWidget);
    });
  });

  group('goldens', () {
    void cardSize(WidgetTester tester, double height) {
      tester.view.physicalSize = Size(390, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    for (final brightness in Brightness.values) {
      testWidgets('Ernährungsübersicht ${brightness.name}', (tester) async {
        cardSize(tester, 400);
        await _pumpCard(tester, _underTarget, brightness: brightness);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(CupertinoApp),
          matchesGoldenFile(
            'goldens/calendar_nutrition_${brightness.name}.png',
          ),
        );
      }, tags: ['golden']);
    }

    testWidgets('Ernährungsübersicht über Ziel dunkel', (tester) async {
      cardSize(tester, 400);
      await _pumpCard(
        tester,
        const CalendarNutrition(
          kilocalories: 3000,
          proteinGrams: 200,
          carbohydrateGrams: 340,
          fatGrams: 95,
          target: _target,
        ),
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/calendar_nutrition_over_dark.png'),
      );
    }, tags: ['golden']);

    testWidgets('Ernährungsübersicht ohne Ziel', (tester) async {
      cardSize(tester, 400);
      await _pumpCard(
        tester,
        const CalendarNutrition(
          kilocalories: 1240,
          proteinGrams: 82,
          carbohydrateGrams: 120,
          fatGrams: 41,
        ),
      );
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/calendar_nutrition_no_target_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('Ernährungsübersicht Textgröße 2', (tester) async {
      cardSize(tester, 840);
      await _pumpCard(tester, _underTarget, textScale: 2);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/calendar_nutrition_scale2_light.png'),
      );
    }, tags: ['golden']);
  });
}
