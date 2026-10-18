import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/api_nutrition_online_provider.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  test(
    'failed day selection keeps the previous matching snapshot and can retry',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _ControlledNutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await viewModel.load();
      final oldSnapshot = viewModel.snapshot;
      final pending = Completer<NutritionSnapshot>();
      repository.pendingReads['2026-10-13'] = pending;

      final selecting = viewModel.selectDate('2026-10-13');
      pending.completeError(StateError('temporary read failure'));
      await selecting;

      expect(viewModel.snapshot, same(oldSnapshot));
      expect(viewModel.localDate, '2026-10-12');
      expect(viewModel.snapshot!.day.localDate, viewModel.localDate);
      expect(viewModel.errorOperation, NutritionErrorOperation.day);
      expect(viewModel.errorMessage, contains('temporary read failure'));

      repository.pendingReads.remove('2026-10-13');
      await viewModel.load();
      expect(viewModel.localDate, '2026-10-13');
      expect(viewModel.snapshot!.day.localDate, '2026-10-13');
      expect(viewModel.errorMessage, isNull);
      viewModel.dispose();
    },
  );

  test('overlapping day reads only publish the latest selected date', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _ControlledNutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await viewModel.load();
    final earlier = Completer<NutritionSnapshot>();
    final latest = Completer<NutritionSnapshot>();
    repository.pendingReads['2026-10-13'] = earlier;
    repository.pendingReads['2026-10-14'] = latest;

    final firstSelection = viewModel.selectDate('2026-10-13');
    final secondSelection = viewModel.selectDate('2026-10-14');
    latest.complete(_snapshotFor('2026-10-14'));
    await secondSelection;
    earlier.complete(_snapshotFor('2026-10-13'));
    await firstSelection;

    expect(viewModel.localDate, '2026-10-14');
    expect(viewModel.snapshot!.day.localDate, '2026-10-14');
    expect(viewModel.isLoading, isFalse);
    viewModel.dispose();
  });

  testWidgets('failed diary removal remains visible on the day overview', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _ControlledNutritionRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    )..failRemoval = true;
    const entryId = '00000000-0000-4000-8000-000000000099';
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: entryId,
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Joghurt',
        brand: null,
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: null,
      ),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(ValueKey('nutrition-entry-$entryId')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();

    expect(viewModel.errorOperation, NutritionErrorOperation.diary);
    expect(
      find.text(viewModel.errorMessage!),
      findsOneWidget,
      reason:
          '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
    );
    expect(viewModel.snapshot!.day.entries.single.entryId, entryId);
    viewModel.dispose();
  });

  testWidgets(
    'failed entry save stays in editor and remains visible after cancel',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _ControlledNutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      const entryId = '00000000-0000-4000-8000-000000000098';
      await repository.saveEntry(
        '2026-10-12',
        NutritionEntry(
          entryId: entryId,
          meal: NutritionMeal.breakfast,
          position: 0,
          productName: 'Joghurt',
          brand: null,
          amountGrams: 100,
          per100Grams: const NutritionTotals(kilocalories: 60),
          source: null,
        ),
      );
      repository.failSave = true;
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(ValueKey('nutrition-entry-$entryId'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sichern'));
      await tester.pumpAndSettle();

      expect(find.text('Eintrag bearbeiten'), findsOneWidget);
      expect(
        find.text(viewModel.errorMessage!),
        findsOneWidget,
        reason:
            '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
      );
      expect(viewModel.snapshot!.day.entries.single.productName, 'Joghurt');
      expect(viewModel.errorOperation, NutritionErrorOperation.diary);
      await tester.tap(find.byKey(const ValueKey('nutrition-edit-close')));
      await tester.pumpAndSettle();
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.errorOperation, NutritionErrorOperation.diary);
      expect(
        find.text(viewModel.errorMessage!),
        findsOneWidget,
        reason:
            '${viewModel.errorMessage} / ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
      );
      viewModel.dispose();
    },
  );

  testWidgets('manual diary entry is persisted as one local sync mutation', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      ids: () => '00000000-0000-4000-8000-000000000005',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mahlzeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mittagessen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manuell erfassen'));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('nutrition-entry-name'));
    final amount = find.byKey(const ValueKey('nutrition-entry-amount'));
    final kcal = find.byKey(const ValueKey('nutrition-entry-kcal'));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Haferflocken');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '60');
    await tester.ensureVisible(kcal);
    await tester.enterText(kcal, '370');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Manuell speichern'),
      240,
      scrollable: _verticalScrollable(),
    );
    await tester.ensureVisible(find.text('Manuell speichern'));
    await tester.tap(find.text('Manuell speichern'));
    await tester.pumpAndSettle();

    expect(viewModel.snapshot!.day.entries.single.productName, 'Haferflocken');
    expect(viewModel.snapshot!.day.entries.single.meal.name, 'lunch');
    expect(
      await store.readOutbox(aggregateType: 'nutrition-day'),
      hasLength(1),
    );
    expect(viewModel.statusMessage, contains('lokal gespeichert'));
  });

  testWidgets('nutrition overview keeps forms behind contextual routes', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Montag, 12. Oktober'), findsOneWidget);
    expect(find.byKey(const ValueKey('nutrition-add-food')), findsOneWidget);
    expect(find.text('Gerichte und Ziele verwalten'), findsNothing);
    expect(find.text('Noch nichts eingetragen'), findsAtLeastNWidgets(1));
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.byKey(const ValueKey('meal-add-breakfast')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('meal-add-breakfast')));
    await tester.pumpAndSettle();
    expect(viewModel.selectedMeal, NutritionMeal.breakfast);
    expect(find.byType(CupertinoTextField), findsNothing);
    await tester.tap(find.text('Manuell erfassen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('nutrition-entry-kcal')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nutrition-entry-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.day.entries, isEmpty);
    expect(await store.readOutbox(aggregateType: 'nutrition-day'), isEmpty);
    expect(find.byKey(const ValueKey('nutrition-entry-name')), findsNothing);
  });

  testWidgets('opening the diary is local and action errors stay contextual', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final online = _FailingNutritionOnlineProvider();
    final repository = NutritionRepository(
      store: store,
      online: online,
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(online.searchCalls, 0);
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lebensmittel suchen'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('nutrition-entry-search'));
    await tester.scrollUntilVisible(
      search,
      220,
      scrollable: _verticalScrollable(),
    );
    await tester.enterText(search, 'Haferdrink');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(online.searchCalls, 1);
    expect(
      find.textContaining('Fehlerkennung: nutrition_import_not_supported'),
      findsOneWidget,
    );
    expect(viewModel.errorOperation, NutritionErrorOperation.search);

    await tester.tap(find.text('Optionen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nutrition-entry-close')));
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
    await tester.pumpAndSettle();
    expect(find.textContaining('nutrition_import_not_supported'), findsNothing);
    expect(viewModel.snapshot!.day.localDate, '2026-10-12');
  });

  testWidgets('day navigation and edit preserve food source provenance', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    var nextId = 15;
    final repository = NutritionRepository(
      store: store,
      ids: () =>
          '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final source = NutritionSource(
      provider: 'Open Food Facts',
      barcode: '1234567890123',
      retrievedAtUtc: DateTime.utc(2026, 10, 1),
      basisGrams: 100,
    );
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: '00000000-0000-4000-8000-000000000016',
        meal: NutritionMeal.breakfast,
        position: 0,
        productName: 'Joghurt',
        brand: 'Marke',
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: source,
      ),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.chevron_left).first);
    await tester.pumpAndSettle();
    expect(viewModel.localDate, '2026-10-11');
    expect(viewModel.snapshot!.day.localDate, '2026-10-11');
    await tester.tap(find.byIcon(CupertinoIcons.chevron_right).first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('nutrition-entry-00000000-0000-4000-8000-000000000016'),
      ),
      250,
      scrollable: _verticalScrollable(),
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('nutrition-entry-00000000-0000-4000-8000-000000000016'),
      ),
    );
    await tester.pumpAndSettle();
    final amountField = find.byKey(const ValueKey('nutrition-edit-amount'));
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    await tester.enterText(amountField, '175');
    expect(
      tester.widget<CupertinoTextField>(amountField).controller!.text,
      '175',
    );
    await tester.ensureVisible(find.text('Sichern'));
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();

    expect(viewModel.errorMessage, isNull, reason: viewModel.errorMessage);
    final edited = viewModel.snapshot!.day.entries.single;
    expect(edited.amountGrams, 175);
    expect(edited.source?.barcode, '1234567890123');
    expect(edited.source?.provider, 'Open Food Facts');
  });

  testWidgets(
    'manual recipe scales into immutable diary snapshots and archives',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      var nextId = 25;
      final repository = NutritionRepository(
        store: store,
        ids: () =>
            '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 12, 10),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      await _openPlanning(tester);

      await tester.scrollUntilVisible(
        find.text('Neues Gericht anlegen'),
        260,
        scrollable: _verticalScrollable(),
      );
      await tester.ensureVisible(find.text('Neues Gericht anlegen'));
      await tester.tap(find.text('Neues Gericht anlegen'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      await tester.enterText(find.byType(CupertinoTextField).at(0), 'Porridge');
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-0-name')),
        'Hafer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-0-brand')),
        'Bio',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-0-amount')),
        '50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-0-kcal')),
        '380',
      );
      await tester.scrollUntilVisible(
        find.text('Bestandteil hinzufügen'),
        220,
        scrollable: _verticalScrollable(),
      );
      await tester.tap(find.text('Bestandteil hinzufügen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('nutrition-recipe-component-1-name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-1-name')),
        'Milch',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-1-amount')),
        '25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nutrition-recipe-component-1-kcal')),
        '60',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sichern'));
      await tester.tap(find.text('Sichern'));
      await tester.pumpAndSettle();
      expect(viewModel.snapshot!.meals.single.value.components, hasLength(2));
      expect(
        viewModel.snapshot!.meals.single.value.components.first.brand,
        'Bio',
      );

      await tester.longPress(find.text('Porridge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, '2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Übernehmen').last);
      await tester.pumpAndSettle();
      expect(
        viewModel.snapshot!.day.entries
            .map((entry) => entry.amountGrams)
            .toList(),
        [100, 50],
      );

      await tester.longPress(find.text('Porridge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivieren'));
      await tester.pumpAndSettle();
      expect(viewModel.snapshot!.meals.single.value.status, 'Archived');
      expect(
        viewModel.snapshot!.day.entries
            .map((entry) => entry.amountGrams)
            .toList(),
        [100, 50],
      );
    },
  );

  testWidgets('target phase form uses 4/4/9 and cancellation writes nothing', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      ids: () => '00000000-0000-4000-8000-000000000035',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await _openPlanning(tester);

    await tester.scrollUntilVisible(
      find.text('Zielphase hinzufügen'),
      260,
      scrollable: _verticalScrollable(),
    );
    await tester.ensureVisible(find.text('Zielphase hinzufügen'));
    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen').last);
    await tester.pumpAndSettle();
    expect(
      await store.readOutbox(aggregateType: 'nutrition-target-schedule'),
      isEmpty,
    );

    await tester.tap(find.text('Zielphase hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'Aufbau');
    await tester.enterText(fields.at(1), '2026-10-13');
    await tester.ensureVisible(find.text('Sichern'));
    await tester.tap(find.text('Sichern'));
    await tester.pumpAndSettle();
    final phase = viewModel.snapshot!.targetSchedule!.versions.single;
    expect(phase.proteinGrams, 125);
    expect(phase.carbohydrateGrams, 250);
    expect(phase.fatGrams, closeTo(55.56, .01));
  });

  testWidgets(
    'current target phase is read-only while future phase is editable',
    (tester) async {
      _usePhoneViewport(tester);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database: database, accountId: accountId);
      var nextId = 45;
      final repository = NutritionRepository(
        store: store,
        ids: () =>
            '00000000-0000-4000-8000-${(nextId++).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 12, 10),
      );
      final current = _targetPhase(
        id: '00000000-0000-4000-8000-000000000046',
        name: 'Aktuelles Ziel',
        from: '2026-10-01',
        until: '2026-10-19',
      );
      final future = _targetPhase(
        id: '00000000-0000-4000-8000-000000000047',
        name: 'Künftiges Ziel',
        from: '2026-10-20',
      );
      await repository.saveTargetSchedule(
        NutritionTargetSchedule(versions: [current, future]),
      );
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tagesziele · Aktuelles Ziel'), findsOneWidget);
      await _openPlanning(tester);
      await tester.scrollUntilVisible(
        find.text('Aktuelles Ziel'),
        240,
        scrollable: _verticalScrollable(),
      );

      final currentRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000046'),
      );
      expect(
        find.descendant(of: currentRow, matching: find.byType(Dismissible)),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Künftiges Ziel'),
        180,
        scrollable: _verticalScrollable(),
      );
      final futureRow = find.byKey(
        const ValueKey('target-phase-00000000-0000-4000-8000-000000000047'),
      );
      expect(
        find.descendant(of: futureRow, matching: find.byType(Dismissible)),
        findsOneWidget,
      );
      final outboxBefore = await store.readOutbox(
        aggregateType: 'nutrition-target-schedule',
      );
      expect(outboxBefore, hasLength(1));
      expect(
        await store.readOutbox(aggregateType: 'nutrition-target-schedule'),
        hasLength(1),
      );
    },
  );
  testWidgets('swiping an entry left deletes only after confirmation', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt']);
    final key = ValueKey('nutrition-entry-${harness.entryIds.single}');

    await tester.drag(find.byKey(key), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Eintrag löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries, hasLength(1));
    expect(find.byKey(key), findsOneWidget);

    await tester.drag(find.byKey(key), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries, isEmpty);
    expect(find.byKey(key), findsNothing);
    expect(find.text('Noch nichts eingetragen'), findsAtLeastNWidgets(1));
  });

  testWidgets('long press opens the entry sheet with a destructive remove', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt', 'Haferflocken']);
    final key = ValueKey('nutrition-entry-${harness.entryIds.first}');

    await tester.longPress(find.byKey(key));
    await tester.pumpAndSettle();
    expect(find.text('Verschieben'), findsOneWidget);
    expect(find.text('Entfernen'), findsOneWidget);

    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(harness.viewModel.snapshot!.day.entries.map((e) => e.productName), [
      'Haferflocken',
    ]);
  });

  testWidgets('moving an entry in the reorder sheet persists the new order', (
    tester,
  ) async {
    final harness = await _pumpDiary(tester, ['Joghurt', 'Haferflocken']);

    await tester.longPress(
      find.byKey(ValueKey('nutrition-entry-${harness.entryIds.first}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verschieben'));
    await tester.pumpAndSettle();
    expect(find.text('Einträge anordnen'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReorderableDragStartListener).first),
    );
    await tester.pump();
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    final ordered = [...harness.viewModel.snapshot!.day.entries]
      ..sort((a, b) => a.position.compareTo(b.position));
    expect(ordered.map((e) => e.productName), ['Haferflocken', 'Joghurt']);
  });

  testWidgets('future target phase is removed by swipe after confirmation', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    const futureId = '00000000-0000-4000-8000-000000000047';
    await repository.saveTargetSchedule(
      NutritionTargetSchedule(
        versions: [
          _targetPhase(
            id: '00000000-0000-4000-8000-000000000046',
            name: 'Aktuelles Ziel',
            from: '2026-10-01',
            until: '2026-10-19',
          ),
          _targetPhase(
            id: futureId,
            name: 'Künftiges Ziel',
            from: '2026-10-20',
          ),
        ],
      ),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();
    await _openPlanning(tester);

    final row = find.byKey(const ValueKey('target-phase-$futureId'));
    await tester.scrollUntilVisible(
      row,
      180,
      scrollable: _verticalScrollable(),
    );
    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Zielphase entfernen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(
      (await store.readOutbox(aggregateType: 'nutrition-target-schedule')),
      hasLength(1),
    );

    await tester.drag(row, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen').last);
    await tester.pumpAndSettle();
    expect(viewModel.snapshot!.targetSchedule!.versions, hasLength(1));
    expect(
      viewModel.snapshot!.targetSchedule!.versions.single.name,
      'Aktuelles Ziel',
    );
    viewModel.dispose();
  });
}

class _DiaryHarness {
  const _DiaryHarness({required this.viewModel, required this.entryIds});

  final NutritionViewModel viewModel;
  final List<String> entryIds;
}

/// Zeigt das Tagebuch des 12. Oktober mit einem Breakfast-Eintrag je Name.
Future<_DiaryHarness> _pumpDiary(
  WidgetTester tester,
  List<String> names,
) async {
  _usePhoneViewport(tester);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = NutritionRepository(
    store: LocalSyncStore(database: database, accountId: accountId),
    clock: () => DateTime.utc(2026, 10, 12, 10),
  );
  final entryIds = <String>[];
  for (var index = 0; index < names.length; index++) {
    final entryId =
        '00000000-0000-4000-8000-${(200 + index).toString().padLeft(12, '0')}';
    entryIds.add(entryId);
    await repository.saveEntry(
      '2026-10-12',
      NutritionEntry(
        entryId: entryId,
        meal: NutritionMeal.breakfast,
        position: index,
        productName: names[index],
        brand: null,
        amountGrams: 100,
        per100Grams: const NutritionTotals(kilocalories: 60),
        source: null,
      ),
    );
  }
  final viewModel = NutritionViewModel(
    repository: repository,
    localDate: '2026-10-12',
  );
  await tester.pumpWidget(
    CupertinoApp(home: NutritionScreen(viewModel: viewModel)),
  );
  await tester.pumpAndSettle();
  return _DiaryHarness(viewModel: viewModel, entryIds: entryIds);
}

NutritionTargetVersion _targetPhase({
  required String id,
  required String name,
  required String from,
  String? until,
}) => NutritionTargetVersion(
  targetVersionId: id,
  name: name,
  category: NutritionTargetCategory.custom,
  effectiveFrom: from,
  effectiveUntil: until,
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2000,
  proteinGrams: 125,
  carbohydrateGrams: 250,
  fatGrams: 55,
  proteinPercent: null,
  carbohydratePercent: null,
  fatPercent: null,
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

NutritionSnapshot _snapshotFor(String date) => NutritionSnapshot(
  day: NutritionDay(localDate: date, entries: const []),
  meals: const [],
  targetSchedule: null,
  recentFoods: const [],
);

class _ControlledNutritionRepository extends NutritionRepository {
  _ControlledNutritionRepository({required super.store});

  final Map<String, Completer<NutritionSnapshot>> pendingReads = {};
  bool failRemoval = false;
  bool failSave = false;

  @override
  Future<NutritionSnapshot> read(String localDate) {
    final pending = pendingReads[localDate];
    return pending?.future ?? super.read(localDate);
  }

  @override
  Future<void> removeEntry(String localDate, String entryId) {
    if (failRemoval) throw StateError('remove failed');
    return super.removeEntry(localDate, entryId);
  }

  @override
  Future<void> saveEntry(String localDate, NutritionEntry entry) {
    if (failSave) throw StateError('save failed');
    return super.saveEntry(localDate, entry);
  }
}

class _FailingNutritionOnlineProvider implements NutritionOnlineProvider {
  int searchCalls = 0;

  @override
  Future<List<NutritionFood>> searchFoods(String query) async {
    searchCalls++;
    throw const NutritionOnlineException(
      'Suche',
      422,
      'nutrition_import_not_supported',
      'Der Dienst hat die Anfrage abgelehnt. Prüfe die Eingabe oder verwende '
          'die manuelle Eingabe.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openPlanning(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nutrition-more-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gerichte und Ziele verwalten'));
  await tester.pumpAndSettle();
}

Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);
