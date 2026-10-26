import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
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
  }) => repository = _GatedRepository(
    store: LocalSyncStore(database: database, accountId: _accountId),
    ids: () => _id(nextId++),
    clock: () => DateTime.utc(2026, 10, 12, 10),
    online: online,
    capture: capture,
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
  });

  Completer<void>? saveGate;
  int saveCalls = 0;
  bool holdReadAfterSave = false;
  Completer<NutritionSnapshot>? heldRead;
  bool readHeld = false;

  @override
  Future<void> saveEntry(String localDate, NutritionEntry entry) async {
    saveCalls++;
    await saveGate?.future;
    await super.saveEntry(localDate, entry);
    if (holdReadAfterSave) {
      heldRead = Completer<NutritionSnapshot>();
    }
  }

  @override
  Future<NutritionSnapshot> read(String localDate) {
    final held = heldRead;
    if (held != null && !readHeld) {
      readHeld = true;
      return held.future;
    }
    return super.read(localDate);
  }
}

class _EstimateOnline implements NutritionOnlineProvider {
  _EstimateOnline(this.components);

  final List<NutritionEstimateComponent> components;
  int calls = 0;
  Completer<void>? gate;

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
