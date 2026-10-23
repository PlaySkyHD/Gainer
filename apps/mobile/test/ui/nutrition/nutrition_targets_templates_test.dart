import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000007';

const _rest = NutritionDayTarget(
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2200,
  proteinGrams: 180,
  carbohydrateGrams: 190,
  fatGrams: 80,
);

class _Harness {
  _Harness(this.viewModel, this.store, this.repository);

  final NutritionViewModel viewModel;
  final LocalSyncStore store;
  final NutritionRepository repository;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool withTargets = false,
  NutritionDayTarget? rest,
  List<String> breakfast = const [],
  String localDate = '2026-10-12',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final store = LocalSyncStore(database: database, accountId: accountId);
  var nextId = 100;
  final repository = NutritionRepository(
    store: store,
    ids: () =>
        '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
    clock: () => DateTime.utc(2026, 10, 12, 10),
    // Ohne Rhythmus und Trainings ist jeder Tag automatisch ein Ruhetag.
    scheduleProjection: () async => TrainingScheduleProjection(
      schedule: null,
      plans: const [],
      workouts: const [],
      today: LocalDay(2026, 10, 12),
    ),
  );
  if (withTargets) {
    await tester.runAsync(
      () => repository.saveTargets(
        training: const NutritionDayTarget(
          inputMode: NutritionTargetInputMode.grams,
          kilocalories: 2600,
          proteinGrams: 180,
          carbohydrateGrams: 290,
          fatGrams: 80,
        ),
        restDay: rest,
        saltGrams: null,
      ),
    );
  }
  for (var index = 0; index < breakfast.length; index++) {
    await tester.runAsync(
      () => repository.saveEntry(
        localDate,
        NutritionEntry(
          entryId:
              '00000000-0000-4000-8000-${(900 + index).toString().padLeft(12, '0')}',
          meal: NutritionMeal.breakfast,
          position: index,
          productName: breakfast[index],
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 300),
          source: null,
        ),
      ),
    );
  }
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: localDate,
  );
  await tester.pumpWidget(
    CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
  );
  await tester.pumpAndSettle();
  return _Harness(viewModel, store, repository);
}

Future<void> _openMenu(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

GainerPillButton _save(WidgetTester tester) => tester.widget<GainerPillButton>(
  find.byKey(const ValueKey('nutrition-targets-save')),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byType(GainerSheetFrame),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
}

void main() {
  group('targets editor', () {
    testWidgets('uses 4/4/9 defaults and cancelling writes nothing', (
      tester,
    ) async {
      final harness = await _pump(tester);
      await _openMenu(tester, 'Ziele');
      await tester.tap(find.byKey(const ValueKey('nutrition-targets-close')));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => harness.store.readOutbox(
            aggregateType: 'nutrition-target-schedule',
          ),
        ),
        isEmpty,
      );

      await _openMenu(tester, 'Ziele');
      expect(find.text('Ziel pro Tag'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nutrition-targets-save')));
      await tester.pumpAndSettle();
      final version =
          harness.viewModel.snapshot!.targetSchedule!.versions.single;
      expect(version.effectiveFrom, '2026-10-12');
      expect(version.name, 'Ziele');
      expect(version.proteinGrams, 125);
      expect(version.carbohydrateGrams, 250);
      expect(version.fatGrams, closeTo(55.56, .01));
      expect(version.restDay, isNull);
      // Der Standard von 6 g bleibt offen, statt fest gespeichert zu werden.
      expect(version.saltGrams, isNull);
    });

    testWidgets('stores a custom salt limit and rejects 0 g', (tester) async {
      final harness = await _pump(tester);
      await _openMenu(tester, 'Ziele');
      final salt = find.byKey(const ValueKey('nutrition-target-salt'));
      await _scrollTo(tester, salt);
      expect(tester.widget<CupertinoTextField>(salt).controller!.text, '6');
      await tester.enterText(salt, '0');
      await tester.pump();
      expect(_save(tester).onPressed, isNull);
      expect(
        find.text('Die Salzgrenze muss zwischen 0 und 100 g liegen.'),
        findsOneWidget,
      );
      await tester.enterText(salt, '5');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-targets-save')));
      await tester.pumpAndSettle();
      expect(
        harness.viewModel.snapshot!.targetSchedule!.versions.single.saltGrams,
        5,
      );
    });

    testWidgets('rest day target: invalid percentages block saving', (
      tester,
    ) async {
      final harness = await _pump(tester);
      await _openMenu(tester, 'Ziele');
      await tester.tap(
        find.byKey(const ValueKey('nutrition-targets-rest-switch')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trainingstag'), findsOneWidget);
      final restCarbs = find.byKey(
        const ValueKey('nutrition-targets-rest-carbs'),
      );
      await _scrollTo(tester, restCarbs);
      await tester.enterText(restCarbs, '40');
      await tester.pump();
      expect(_save(tester).onPressed, isNull);
      expect(
        find.textContaining('Makroanteile müssen zusammen 100 % ergeben'),
        findsOneWidget,
      );

      await tester.enterText(restCarbs, '50');
      final restKcal = find.byKey(
        const ValueKey('nutrition-targets-rest-kcal'),
      );
      await _scrollTo(tester, restKcal);
      await tester.enterText(restKcal, '1800');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nutrition-targets-save')));
      await tester.pumpAndSettle();
      final version =
          harness.viewModel.snapshot!.targetSchedule!.versions.single;
      expect(version.kilocalories, 2000);
      expect(version.restDay?.kilocalories, 1800);
      expect(version.restDay?.inputMode, NutritionTargetInputMode.percent);
    });

    testWidgets('planning lists training and rest day targets', (tester) async {
      await _pump(tester, withTargets: true, rest: _rest);
      await _openMenu(tester, 'Gerichte und Vorlagen verwalten');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('nutrition-targets-rest')),
        240,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      expect(
        find.byKey(const ValueKey('nutrition-targets-training')),
        findsOneWidget,
      );
      expect(find.textContaining('2.200 kcal'), findsOneWidget);
    });
  });

  group('day kind', () {
    testWidgets('chip shows the rest day target and can be overridden', (
      tester,
    ) async {
      final harness = await _pump(tester, withTargets: true, rest: _rest);
      expect(find.text('Ruhetag'), findsOneWidget);
      expect(find.text('0 von 2.200 kcal'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nutrition-day-kind-chip')));
      await tester.pumpAndSettle();
      expect(find.text('Automatisch (Ruhetag)'), findsOneWidget);
      await tester.tap(find.text('Trainingstag'));
      await tester.pumpAndSettle();
      expect(find.text('Trainingstag · manuell'), findsOneWidget);
      expect(find.text('0 von 2.600 kcal'), findsOneWidget);
      expect(
        harness.viewModel.snapshot!.day.dayKind,
        NutritionDayKind.training,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('nutrition-day-kind-chip')))
            .label
            .trim(),
        'Tagesart: Trainingstag, manuell festgelegt. Ändern',
      );

      await tester.tap(find.byKey(const ValueKey('nutrition-day-kind-chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatisch (Ruhetag)'));
      await tester.pumpAndSettle();
      expect(find.text('Ruhetag'), findsOneWidget);
      expect(harness.viewModel.snapshot!.day.dayKind, isNull);
    });

    testWidgets('without a rest day target there is no chip', (tester) async {
      await _pump(tester, withTargets: true);
      expect(
        find.byKey(const ValueKey('nutrition-day-kind-chip')),
        findsNothing,
      );
      expect(find.text('0 von 2.600 kcal'), findsOneWidget);
    });
  });

  group('day templates', () {
    testWidgets('saving is disabled on an empty day', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Der Tag hat noch keine Einträge.'), findsOneWidget);
      await tester.tap(find.text('Tag als Vorlage speichern'));
      await tester.pumpAndSettle();
      // Die Aktion ist deaktiviert; das Menü bleibt offen.
      expect(find.text('Als Vorlage speichern'), findsNothing);
      expect(find.text('Tag als Vorlage speichern'), findsOneWidget);
    });

    testWidgets('save, then apply to another day with append and replace', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        breakfast: ['Haferflocken', 'Banane'],
      );
      await _openMenu(tester, 'Tag als Vorlage speichern');
      await tester.enterText(
        find.byKey(const ValueKey('template-name')),
        'Trainingstag',
      );
      await tester.tap(find.byKey(const ValueKey('template-kind-training')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();
      final template = harness.viewModel.snapshot!.templates.single;
      expect(template.name, 'Trainingstag');
      expect(template.dayKind, NutritionDayKind.training);

      // Morgen: leerer Tag, Vorlage wird direkt übernommen.
      await harness.viewModel.selectDate('2026-10-13');
      await tester.pumpAndSettle();
      await _openMenu(tester, 'Aus Vorlage befüllen');
      await tester.tap(find.text('Trainingstag'));
      await tester.pumpAndSettle();
      expect(harness.viewModel.snapshot!.day.entries, hasLength(2));

      // Gefüllter Tag: Hinzufügen hängt an, Ersetzen ersetzt.
      await _openMenu(tester, 'Aus Vorlage befüllen');
      await tester.tap(find.text('Trainingstag'));
      await tester.pumpAndSettle();
      expect(find.text('Der Tag hat schon Einträge'), findsOneWidget);
      await tester.tap(find.text('Hinzufügen').last);
      await tester.pumpAndSettle();
      expect(harness.viewModel.snapshot!.day.entries, hasLength(4));

      await _openMenu(tester, 'Aus Vorlage befüllen');
      await tester.tap(find.text('Trainingstag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ersetzen').last);
      await tester.pumpAndSettle();
      expect(harness.viewModel.snapshot!.day.entries, hasLength(2));
    });

    testWidgets('overwriting asks first and keeps the name', (tester) async {
      final harness = await _pump(tester, breakfast: ['Haferflocken']);
      await tester.runAsync(
        () => harness.repository.saveDayAsTemplate(
          '2026-10-12',
          name: 'Ruhetag',
          dayKind: NutritionDayKind.rest,
        ),
      );
      await tester.runAsync(
        () => harness.repository.saveEntry(
          '2026-10-12',
          NutritionEntry(
            entryId: '00000000-0000-4000-8000-000000000950',
            meal: NutritionMeal.lunch,
            position: 0,
            productName: 'Reis',
            brand: null,
            amountGrams: 150,
            per100Grams: const NutritionTotals(kilocalories: 130),
            source: null,
          ),
        ),
      );
      await harness.viewModel.load();
      await tester.pumpAndSettle();

      await _openMenu(tester, 'Tag als Vorlage speichern');
      await tester.tap(find.text('Überschreiben'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('template-overwrite-Ruhetag')),
      );
      await tester.pumpAndSettle();
      expect(find.text('„Ruhetag“ überschreiben?'), findsOneWidget);
      await tester.tap(find.text('Überschreiben').last);
      await tester.pumpAndSettle();
      final template = harness.viewModel.snapshot!.templates.single;
      expect(template.name, 'Ruhetag');
      expect(template.dayKind, NutritionDayKind.rest);
      expect(template.entries, hasLength(2));
    });

    testWidgets('an empty future day suggests the matching template', (
      tester,
    ) async {
      final harness = await _pump(tester, breakfast: ['Haferflocken']);
      await tester.runAsync(
        () => harness.repository.saveDayAsTemplate(
          '2026-10-12',
          name: 'Ruhetag',
          dayKind: NutritionDayKind.rest,
        ),
      );
      await harness.viewModel.selectDate('2026-10-13');
      await tester.pumpAndSettle();
      expect(find.text('Vorlage „Ruhetag“ übernehmen'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(harness.viewModel.snapshot!.day.entries, hasLength(1));
      expect(find.text('Vorlage „Ruhetag“ übernehmen'), findsNothing);
    });

    testWidgets('the template editor edits, moves, removes and adds entries', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        breakfast: ['Haferflocken', 'Banane'],
      );
      await tester.runAsync(
        () => harness.repository.saveDayAsTemplate(
          '2026-10-12',
          name: 'Trainingstag',
        ),
      );
      await harness.viewModel.load();
      await tester.pumpAndSettle();
      await _openMenu(tester, 'Gerichte und Vorlagen verwalten');
      final row = find.byKey(const ValueKey('day-template-Trainingstag'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Vorlage bearbeiten'), findsOneWidget);

      // Menge ändern.
      await tester.tap(find.text('Haferflocken'));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag bearbeiten'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('meal-component-amount')),
        '50',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sichern').last);
      await tester.pumpAndSettle();
      expect(find.text('50 g · 150 kcal'), findsOneWidget);

      // Entfernen per Wischen nach Bestätigung.
      await tester.drag(find.text('Banane'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen').last);
      await tester.pumpAndSettle();
      expect(find.text('Banane'), findsNothing);

      // In eine andere Mahlzeit verschieben.
      await tester.longPress(find.text('Haferflocken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Andere Mahlzeit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snacks').last);
      await tester.pumpAndSettle();

      // Über den gemeinsamen Dialog zum Mittagessen hinzufügen.
      final addLunch = find.byKey(const ValueKey('day-template-add-lunch'));
      await tester.ensureVisible(addLunch);
      await tester.tap(addLunch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manuell erfassen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-name')),
        'Reis',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-amount')),
        '150',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-kcal')),
        '130',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sichern').last);
      await tester.pumpAndSettle();
      final template = harness.viewModel.snapshot!.templates.single;
      expect(
        [
          for (final e in template.entries)
            (e.meal, e.productName, e.amountGrams),
        ],
        [
          (NutritionMeal.lunch, 'Reis', 150.0),
          (NutritionMeal.snacks, 'Haferflocken', 50.0),
        ],
      );
      // Der Tag, aus dem die Vorlage stammt, bleibt unverändert.
      expect(harness.viewModel.snapshot!.day.entries, hasLength(2));
    });

    testWidgets('planning lists templates and deletes after confirmation', (
      tester,
    ) async {
      final harness = await _pump(tester, breakfast: ['Haferflocken']);
      await tester.runAsync(
        () => harness.repository.saveDayAsTemplate('2026-10-12', name: 'Weg'),
      );
      await harness.viewModel.load();
      await tester.pumpAndSettle();
      await _openMenu(tester, 'Gerichte und Vorlagen verwalten');
      final row = find.byKey(const ValueKey('day-template-Weg'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.drag(row, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Vorlage löschen?'), findsOneWidget);
      await tester.tap(find.text('Löschen').last);
      await tester.pumpAndSettle();
      expect(harness.viewModel.snapshot!.templates, isEmpty);
      expect(harness.viewModel.snapshot!.day.entries, hasLength(1));
    });
  });
}
