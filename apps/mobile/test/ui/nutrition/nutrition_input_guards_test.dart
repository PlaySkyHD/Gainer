import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/bls_food_catalog.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/nutrition/food_search.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _accountId = '00000000-0000-4000-8000-000000000004';
const _date = '2026-10-12';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

NutritionFood _food(String name) => NutritionFood(
  name: name,
  brand: null,
  per100Grams: const NutritionTotals(kilocalories: 100),
  source: const NutritionSource(provider: 'Open Food Facts', basisGrams: 100),
);

NutritionEstimateComponent _component(String name) =>
    NutritionEstimateComponent(
      name: name,
      amountGrams: 200,
      totals: const NutritionTotals(kilocalories: 300),
      confidence: 'medium',
      dataGaps: const [],
    );

MealEstimateDraft _draft(List<NutritionEstimateComponent> components) =>
    MealEstimateDraft(
      components: components,
      provider: 'OpenAI',
      schemaVersion: 'meal-estimate-v2',
      estimatedAtUtc: DateTime.utc(2026, 10, 12, 10),
    );

void main() {
  late LocalDatabase database;
  late _GatedRepository repository;
  var nextId = 300;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    nextId = 300;
  });

  tearDown(() => database.close());

  _GatedRepository newRepository({
    NutritionOnlineProvider? online,
    CapturePlatform? capture,
    LocalFoodCatalog? localFoods,
  }) => repository = _GatedRepository(
    store: LocalSyncStore(database: database, accountId: _accountId),
    ids: () => _id(nextId++),
    clock: () => DateTime.utc(2026, 10, 12, 10),
    online: online,
    capture: capture,
    localFoods: localFoods,
  );

  group('view model', () {
    test('a second tap on the same estimate component saves nothing', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      final pizza = _component('Pizza');
      final reis = _component('Reis');
      viewModel.mealEstimateDraft = _draft([pizza, reis]);
      repository.saveGate = Completer<void>();

      final first = viewModel.confirmEstimatedComponent(pizza);
      final second = viewModel.confirmEstimatedComponent(pizza);
      repository.saveGate!.complete();
      await Future.wait([first, second]);
      // Auch ein später Tipp nach dem Entfernen bucht nichts.
      await viewModel.confirmEstimatedComponent(pizza);

      expect(repository.saveCalls, 1);
      expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
        'Pizza',
      ]);
      expect(viewModel.mealEstimateDraft!.components, [reis]);
    });

    test('a rejected removal and move return false', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      await viewModel.addFood(_food('Apfel'), amountGrams: 100);
      final id = viewModel.snapshot!.day.entries.single.entryId;
      repository.saveGate = Completer<void>();
      final saving = viewModel.addFood(_food('Birne'), amountGrams: 100);

      expect(await viewModel.removeEntry(id), isFalse);
      expect(await viewModel.moveEntry(id, NutritionMeal.dinner, 0), isFalse);
      viewModel.reportRejected(NutritionErrorOperation.diary);
      expect(viewModel.errorMessage, NutritionViewModel.rejectedMessage);

      repository.saveGate!.complete();
      await saving;
      expect(viewModel.snapshot!.day.entries, hasLength(2));
    });

    test('a rejected search during a failing save keeps the real error and a '
        'rejected save does not show a stale one', () async {
      final online = _EstimateOnline([_component('Pizza')])
        ..gate = Completer<void>();
      final viewModel = NutritionViewModel(
        repository: newRepository(online: online),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();
      repository.saveError = LocalResourceChangedException();

      final estimating = viewModel.estimateMeal('Pizza');
      await Future<void>.delayed(Duration.zero);
      final saving = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      // Die Suche wird abgewiesen, weil die Schätzung liest.
      await viewModel.searchFoods('Apfel');
      repository.saveGate!.complete();

      expect(await saving, isFalse);
      expect(
        viewModel.failureMessage(),
        isNot(NutritionViewModel.rejectedMessage),
      );
      expect(viewModel.failureMessage(), contains('Synchronisieren'));

      online.gate!.complete();
      await estimating;
      // Eine abgewiesene Mutation meldet sich selbst, nicht den alten Fehler.
      repository.saveGate = Completer<void>();
      final first = viewModel.addFood(_food('Birne'), amountGrams: 100);
      expect(await viewModel.addFood(_food('Kiwi'), amountGrams: 100), isFalse);
      expect(viewModel.failureMessage(), NutritionViewModel.rejectedMessage);
      repository.saveGate!.complete();
      await first;
    });

    test('an invalid estimate component reports a message instead of '
        'throwing', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      const empty = NutritionEstimateComponent(
        name: 'Nichts',
        amountGrams: 0,
        totals: NutritionTotals(kilocalories: 0),
        confidence: 'low',
        dataGaps: [],
      );
      viewModel.mealEstimateDraft = _draft([empty]);

      expect(await viewModel.confirmEstimatedComponent(empty), isFalse);

      expect(viewModel.errorMessage, contains('nicht gültig'));
      expect(repository.saveCalls, 0);
    });

    test('a double tap leaves no stale rejection after the first save '
        'succeeds', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();

      final first = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      final second = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      repository.saveGate!.complete();

      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.errorOperation, isNull);
    });

    test('a second action while saving is ignored', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();

      final first = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      final second = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      repository.saveGate!.complete();
      await Future.wait([first, second]);

      expect(repository.saveCalls, 1);
      expect(viewModel.snapshot!.day.entries, hasLength(1));
    });

    test('a save does not block a search or the day load afterwards', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();

      await viewModel.addFood(_food('Apfel'), amountGrams: 100);
      await viewModel.addFood(_food('Birne'), amountGrams: 100);
      await viewModel.selectDate('2026-10-13');

      expect(viewModel.snapshot!.day.entries, isEmpty);
      expect(viewModel.localDate, '2026-10-13');
    });

    test(
      'a running estimate does not block saving; the save reports true',
      () async {
        final online = _EstimateOnline([_component('Pizza')])
          ..gate = Completer<void>();
        final viewModel = NutritionViewModel(
          repository: newRepository(online: online),
          localDate: _date,
        );
        addTearDown(viewModel.dispose);
        await viewModel.load();

        final estimating = viewModel.estimateMeal('Pizza');
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.isOnlineOperation, isTrue);
        final saved = await viewModel.addFood(_food('Apfel'), amountGrams: 100);
        online.gate!.complete();
        await estimating;

        expect(saved, isTrue);
        expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
          'Apfel',
        ]);
        expect(viewModel.mealEstimateDraft!.components.single.name, 'Pizza');
      },
    );

    test('a rejected second save reports false', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();

      final first = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      final second = await viewModel.addFood(_food('Apfel'), amountGrams: 100);
      repository.saveGate!.complete();

      expect(second, isFalse);
      expect(await first, isTrue);
    });

    test('a failed save reports false', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveError = LocalResourceChangedException();

      final saved = await viewModel.addFood(_food('Apfel'), amountGrams: 100);

      expect(saved, isFalse);
      // Deutsche Meldung statt der englischen des Stores.
      expect(
        viewModel.errorMessage,
        'Der Tag hat sich gerade beim Synchronisieren geändert. '
        'Bitte versuche es noch einmal.',
      );
    });

    test('a save is rejected while the day changes, also after an earlier '
        'save ended', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();
      final nextDay = repository.readGates['2026-10-13'] = Completer<void>();

      final saving = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      final loading = viewModel.selectDate('2026-10-13');
      repository.saveGate!.complete();
      await saving;

      // Das erste Speichern ist fertig, der Tageswechsel läuft noch.
      expect(viewModel.canSave, isFalse);
      final rejected = await viewModel.addFood(
        _food('Birne'),
        amountGrams: 100,
      );
      expect(rejected, isFalse);
      expect(repository.saveCalls, 1);

      nextDay.complete();
      await loading;
      expect(viewModel.localDate, '2026-10-13');
      expect(viewModel.canSave, isTrue);
      expect(viewModel.snapshot!.day.entries, isEmpty);
    });

    test('reloading the same day while saving keeps the new entry', () async {
      final viewModel = NutritionViewModel(
        repository: newRepository(),
        localDate: _date,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      repository.saveGate = Completer<void>();
      final staleRead = repository.holdNextRead = Completer<void>();

      final saving = viewModel.addFood(_food('Apfel'), amountGrams: 100);
      // Das Neuladen liest den Stand vor dem Speichern und kommt zuletzt an.
      final loading = viewModel.load();
      await Future<void>.delayed(Duration.zero);
      repository.saveGate!.complete();
      await saving;
      expect(viewModel.snapshot!.day.entries, hasLength(1));
      staleRead.complete();
      await loading;

      expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
        'Apfel',
      ]);
    });

    test(
      'a save result for the old day does not replace the new day',
      () async {
        final viewModel = NutritionViewModel(
          repository: newRepository(),
          localDate: _date,
        );
        addTearDown(viewModel.dispose);
        await viewModel.load();
        repository.holdReadAfterSave = true;

        final saving = viewModel.addFood(_food('Apfel'), amountGrams: 100);
        while (!repository.readHeld) {
          await Future<void>.delayed(Duration.zero);
        }
        await viewModel.selectDate('2026-10-13');
        repository.heldRead!.complete(
          NutritionSnapshot(
            day: NutritionDay(localDate: _date, entries: const []),
            meals: const [],
            targetSchedule: null,
            recentFoods: const [],
          ),
        );
        await saving;

        expect(viewModel.localDate, '2026-10-13');
        expect(viewModel.snapshot!.day.localDate, '2026-10-13');
      },
    );
  });

  group('screen', () {
    Future<NutritionViewModel> pump(
      WidgetTester tester, {
      DictationPlatform? dictation,
      bool seedRecent = false,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (seedRecent) {
        await repository.saveEntry(
          _date,
          NutritionEntry(
            entryId: _id(200),
            meal: NutritionMeal.breakfast,
            position: 0,
            productName: 'Haferflocken',
            brand: null,
            amountGrams: 50,
            per100Grams: const NutritionTotals(kilocalories: 370),
            source: const NutritionSource(
              provider: 'Open Food Facts',
              basisGrams: 100,
            ),
          ),
        );
        repository.saveCalls = 0;
      }
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: _date,
        dictation: dictation,
      );
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();
      return viewModel;
    }

    Future<void> openRecent(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zuletzt verwendet'));
      await tester.pumpAndSettle();
    }

    Future<void> openEstimate(WidgetTester tester, String text) async {
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nutrition-mode-estimate')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-estimate-text')),
        text,
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
    }

    testWidgets('a double tap on a recent food adds it once', (tester) async {
      newRepository();
      final viewModel = await pump(tester, seedRecent: true);
      await openRecent(tester);
      repository.saveGate = Completer<void>();

      final row = find.textContaining('kcal / 100 g');
      await tester.tap(row);
      await tester.pump();
      await tester.tap(row, warnIfMissed: false);
      await tester.pump();
      repository.saveGate!.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expect(viewModel.snapshot!.day.entries, hasLength(2));
    });

    testWidgets('a local hit saves and closes while an online search runs', (
      tester,
    ) async {
      final online = _EstimateOnline(const [])..searchGate = Completer<void>();
      newRepository(online: online, localFoods: _FakeCatalog());
      final viewModel = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('nutrition-mode-search')),
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-mode-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-search')),
        'Apfel',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(viewModel.isOnlineOperation, isTrue);

      await tester.tap(find.textContaining('kcal / 100 g'));
      // Der Ladekreis der laufenden Suche animiert endlos: kein pumpAndSettle.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(repository.saveCalls, 1);
      expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
        'Apfel',
      ]);
      // Das Sheet schloss, weil gespeichert wurde.
      expect(
        find.byKey(const ValueKey('nutrition-entry-search')),
        findsNothing,
      );
      online.searchGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('an empty amount reports an error instead of adding 100 g', (
      tester,
    ) async {
      newRepository();
      final viewModel = await pump(tester, seedRecent: true);
      await openRecent(tester);
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-entry-amount')),
        '',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('kcal / 100 g'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 0);
      expect(viewModel.snapshot!.day.entries, hasLength(1));
      expect(viewModel.errorMessage, contains('Menge'));
    });

    testWidgets('a swipe delete rejected while saving keeps the row and '
        'shows a message', (tester) async {
      newRepository();
      final viewModel = await pump(tester, seedRecent: true);
      final row = find.byKey(ValueKey('nutrition-entry-${_id(200)}'));
      repository.saveGate = Completer<void>();
      final saving = viewModel.addFood(_food('Birne'), amountGrams: 100);
      await tester.pump();
      expect(viewModel.canSave, isFalse);

      // Der Ladekreis des laufenden Speicherns animiert endlos.
      await tester.drag(row, const Offset(-500, 0));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Löschen').last);
      await tester.pump(const Duration(seconds: 1));

      expect(row, findsOneWidget);
      expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
        'Haferflocken',
      ]);
      expect(find.text(NutritionViewModel.rejectedMessage), findsOneWidget);

      repository.saveGate!.complete();
      await saving;
      await tester.pumpAndSettle();
    });

    testWidgets('the suggested template button shows a message when it is '
        'rejected', (tester) async {
      newRepository();
      await repository.saveEntry(
        '2026-10-11',
        NutritionEntry(
          entryId: _id(210),
          meal: NutritionMeal.breakfast,
          position: 0,
          productName: 'Müsli',
          brand: null,
          amountGrams: 50,
          per100Grams: const NutritionTotals(kilocalories: 370),
          source: const NutritionSource(
            provider: 'Open Food Facts',
            basisGrams: 100,
          ),
        ),
      );
      await repository.saveDayAsTemplate(
        '2026-10-11',
        name: 'Standard',
        dayKind: NutritionDayKind.rest,
      );
      repository.saveCalls = 0;
      final viewModel = await pump(tester);
      final suggestion = find.byKey(
        const ValueKey('nutrition-template-suggestion'),
      );
      expect(suggestion, findsOneWidget);
      final button = find.descendant(
        of: suggestion,
        matching: find.byType(GainerPillButton),
      );
      // Der Handler bleibt von einem Tipp kurz vor dem Sperren erhalten.
      final onPressed = tester.widget<GainerPillButton>(button).onPressed!;
      repository.saveGate = Completer<void>();
      final saving = viewModel.addFood(_food('Birne'), amountGrams: 100);
      await tester.pump();
      expect(viewModel.canSave, isFalse);

      onPressed();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(NutritionViewModel.rejectedMessage), findsOneWidget);

      repository.saveGate!.complete();
      await saving;
      await tester.pumpAndSettle();
    });

    testWidgets('a failed entry edit shows the error on the edit page', (
      tester,
    ) async {
      newRepository();
      await pump(tester, seedRecent: true);
      await tester.tap(find.byKey(ValueKey('nutrition-entry-${_id(200)}')));
      await tester.pumpAndSettle();
      repository.saveError = LocalResourceChangedException();

      await tester.tap(find.widgetWithText(GainerPillButton, 'Sichern'));
      await tester.pumpAndSettle();

      const message =
          'Der Tag hat sich gerade beim Synchronisieren geändert. '
          'Bitte versuche es noch einmal.';
      final page = find.ancestor(
        of: find.byKey(const ValueKey('nutrition-edit-close')),
        matching: find.byType(CupertinoPageScaffold),
      );
      expect(page, findsOneWidget);
      expect(
        find.descendant(of: page, matching: find.text(message)),
        findsOneWidget,
      );
    });

    testWidgets('the targets sheet stays open with a message when saving is '
        'rejected', (tester) async {
      newRepository();
      final viewModel = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ziele'));
      await tester.pumpAndSettle();
      repository.saveGate = Completer<void>();
      final saving = viewModel.addFood(_food('Birne'), amountGrams: 100);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('nutrition-targets-save')));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const ValueKey('nutrition-targets-save')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('nutrition-targets-save-error')),
        findsOneWidget,
      );
      expect(find.text(NutritionViewModel.rejectedMessage), findsOneWidget);

      repository.saveGate!.complete();
      await saving;
      await tester.pumpAndSettle();
    });

    testWidgets('a double tap on an estimate component books it once', (
      tester,
    ) async {
      final online = _EstimateOnline([_component('Pizza'), _component('Reis')]);
      newRepository(online: online);
      final viewModel = await pump(tester);
      await openEstimate(tester, 'Pizza und Reis');
      await tester.tap(
        find.widgetWithText(GainerPillButton, 'Mahlzeit schätzen'),
      );
      await tester.pumpAndSettle();
      repository.saveGate = Completer<void>();

      await tester.tap(find.text('Pizza'));
      await tester.pump();
      await tester.tap(find.text('Pizza'), warnIfMissed: false);
      await tester.pump();
      repository.saveGate!.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expect(viewModel.snapshot!.day.entries.map((e) => e.productName), [
        'Pizza',
      ]);
      expect(viewModel.mealEstimateDraft!.components.single.name, 'Reis');
    });

    testWidgets('estimating while dictation finishes sends one request', (
      tester,
    ) async {
      final online = _EstimateOnline([_component('Pizza')])
        ..gate = Completer<void>();
      newRepository(online: online);
      await pump(tester, dictation: _FakeDictation());
      await openEstimate(tester, 'Pizza');
      await tester.tap(find.byKey(const ValueKey('nutrition-dictation')));
      await tester.pump();

      final estimate = find.widgetWithText(
        GainerPillButton,
        'Mahlzeit schätzen',
      );
      await tester.tap(estimate);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(estimate, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      online.gate!.complete();
      await tester.pumpAndSettle();

      expect(online.calls, 1);
    });

    testWidgets('a label amount of zero cannot be saved', (tester) async {
      newRepository(online: _LabelOnline(), capture: _FakeCapture());
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('nutrition-mode-label')),
      );
      await tester.tap(find.byKey(const ValueKey('nutrition-mode-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Etikett fotografieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fortfahren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fotomediathek'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einmalig hochladen'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.descendant(
        of: find.widgetWithText(GainerTextFieldRow, label),
        matching: find.byType(CupertinoTextField),
      );
      GainerPillButton saveButton() => tester.widget<GainerPillButton>(
        find.widgetWithText(GainerPillButton, 'Sichern'),
      );
      await tester.enterText(field('Produktname'), 'Müsli');
      await tester.enterText(field('Menge'), '0');
      await tester.pumpAndSettle();
      expect(saveButton().onPressed, isNull);

      await tester.enterText(field('Menge'), '40');
      await tester.pumpAndSettle();
      expect(saveButton().onPressed, isNotNull);
    });
  });
}

/// Hält Speichern und das Lesen nach dem Speichern an, damit Tests
/// überlappende Abläufe steuern können.
class _GatedRepository extends NutritionRepository {
  _GatedRepository({
    required super.store,
    super.ids,
    super.clock,
    super.online,
    super.capture,
    super.localFoods,
  });

  Completer<void>? saveGate;
  Object? saveError;
  int saveCalls = 0;
  bool holdReadAfterSave = false;
  Completer<NutritionSnapshot>? heldRead;
  bool readHeld = false;

  /// Hält Lesen des Tages an, bis der Completer fertig ist.
  final readGates = <String, Completer<void>>{};

  /// Das nächste Lesen liefert den Stand von jetzt, aber erst nach dem Gate.
  Completer<void>? holdNextRead;

  @override
  Future<void> saveEntry(String localDate, NutritionEntry entry) async {
    saveCalls++;
    await saveGate?.future;
    if (saveError case final error?) throw error;
    await super.saveEntry(localDate, entry);
    if (holdReadAfterSave) {
      heldRead = Completer<NutritionSnapshot>();
    }
  }

  @override
  Future<NutritionSnapshot> read(String localDate) async {
    final held = heldRead;
    if (held != null && !readHeld) {
      readHeld = true;
      return held.future;
    }
    final stale = holdNextRead;
    if (stale != null) {
      holdNextRead = null;
      final snapshot = await super.read(localDate);
      await stale.future;
      return snapshot;
    }
    await readGates[localDate]?.future;
    return super.read(localDate);
  }
}

class _FakeCatalog implements LocalFoodCatalog {
  @override
  String get provider => 'BLS';

  @override
  Future<FoodSearchResult> search(String query) async =>
      const FoodSearchResult([
        LocalFood(
          code: 'B1',
          name: 'Apfel',
          per100Grams: NutritionTotals(kilocalories: 52),
        ),
      ]);
}

class _EstimateOnline implements NutritionOnlineProvider {
  _EstimateOnline(this.components);

  final List<NutritionEstimateComponent> components;
  int calls = 0;
  Completer<void>? gate;
  Completer<void>? searchGate;

  @override
  Future<List<NutritionFood>> searchFoods(String query) async {
    await searchGate?.future;
    return const [];
  }

  @override
  Future<MealEstimateDraft> estimateMeal(String description) async {
    calls++;
    await gate?.future;
    return _draft(components);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _LabelOnline implements NutritionOnlineProvider {
  @override
  Future<NutritionLabelScanDraft> scanLabel({
    required Uint8List image,
    required String mimeType,
  }) async => NutritionLabelScanDraft(
    basis: 'Per100Grams',
    servingMassGrams: null,
    kilocalories: const NutritionLabelFieldDraft(
      originalValue: 400,
      per100Grams: 400,
      status: 'Read',
      evidence: '400 kcal',
    ),
    proteinGrams: _missing,
    carbohydrateGrams: _missing,
    fatGrams: _missing,
    saltGrams: _missing,
    fiberGrams: _missing,
    canConfirm: true,
    provider: 'OpenAI',
    providerModelVersion: 'model',
    parserVersion: 'nutrition-label-v1',
    scannedAtUtc: DateTime.utc(2026, 10, 12, 10),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _missing = NutritionLabelFieldDraft(
  originalValue: null,
  per100Grams: null,
  status: 'Missing',
  evidence: null,
);

class _FakeCapture implements CapturePlatform {
  @override
  Future<CapturedImage?> capturePhoto() => chooseImage();

  @override
  Future<CapturedImage?> chooseImage() async => CapturedImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/jpeg',
  );

  @override
  Future<String?> scanBarcode() async => null;
}

class _FakeDictation implements DictationPlatform {
  DictationStatus status = DictationStatus.idle;

  @override
  Future<DictationState> startDictation({required String localeId}) async {
    status = DictationStatus.listening;
    return _state;
  }

  @override
  Future<DictationState> readDictation() async => _state;

  @override
  Future<void> stopDictation() async => status = DictationStatus.finished;

  @override
  Future<void> cancelDictation() async => status = DictationStatus.idle;

  DictationState get _state => DictationState(status: status, transcript: '');
}
