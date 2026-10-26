import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/body/body_screen.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000003';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('check-in screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      await repository.activateGoal(
        kind: BodyGoalKind.cut,
        startWeightKg: 82,
        targetWeightKg: 76,
        startDate: '2026-10-01',
        targetDate: null,
      );
      final model = BodyViewModel(repository);
      addTearDown(model.dispose);

      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(brightness),
          home: BodyScreen(viewModel: model),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(BodyScreen),
        matchesGoldenFile('goldens/body_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }

  testWidgets('Ruhepuls und HRV: Verlauf, heutige Zeilen und wartender Wert', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now();
    String day(int back) {
      final date = DateTime(now.year, now.month, now.day - back);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }

    var id = 700;
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
      ids: () =>
          '00000000-0000-4000-8000-${(id++).toString().padLeft(12, '0')}',
    );
    await tester.runAsync(() async {
      for (final (back, rate, hrv) in [(6, 60, 45), (3, 58, 50), (0, 57, 55)]) {
        await repository.saveCheckIn(
          localDate: day(back),
          weightKg: 71,
          caloriesKcal: null,
          proteinGrams: null,
          carbohydrateGrams: null,
          fatGrams: null,
          steps: null,
          sleepMinutes: null,
          restingHeartRateBpm: rate,
          restingHrvMs: hrv,
        );
      }
    });
    final model = BodyViewModel(repository);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.forBrightness(Brightness.light),
        home: BodyScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(model.load);
    await tester.pumpAndSettle();

    expect(find.text('Ruhepuls und HRV'), findsOneWidget);
    expect(find.byKey(const ValueKey('resting-history')), findsOneWidget);
    expect(find.text('HRV 55 ms'), findsOneWidget);
    expect(find.text('Ruhepuls 57 bpm'), findsOneWidget);
    // Heute-Zeilen mit Beschriftung.
    expect(find.text('Ruhepuls'), findsOneWidget);
    expect(find.text('57 bpm'), findsOneWidget);
    expect(find.text('HRV (RMSSD)'), findsOneWidget);
    expect(find.text('55 ms'), findsOneWidget);
    // Ohne Gurt-Funktion kein Einstieg in die Messung.
    expect(find.byKey(const ValueKey('body-open-hrv')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wartender Ruhewert erscheint als „wartet auf Check-in“', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await tester.runAsync(
      () => repository.recordRestingMeasurement(
        localDate: today,
        restingHeartRateBpm: 59,
        restingHrvMs: 47,
      ),
    );
    final model = BodyViewModel(repository);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.forBrightness(Brightness.light),
        home: BodyScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(model.load);
    await tester.pumpAndSettle();

    expect(find.text('Noch kein Check-in für heute'), findsOneWidget);
    expect(find.byKey(const ValueKey('body-pending-resting')), findsOneWidget);
    expect(find.text('wartet auf Check-in'), findsWidgets);
    expect(find.text('59 bpm · 47 ms'), findsOneWidget);
  });

  test(
    'BodyViewModel does not notify after disposal during a pending read',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final pendingRead = Completer<BodyTrackingSnapshot>();
      final repository = _PendingBodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
        pendingRead: pendingRead,
      );
      final model = BodyViewModel(repository);
      var notifications = 0;
      model.addListener(() => notifications++);

      final load = model.load();
      expect(notifications, 1);
      model.dispose();
      pendingRead.complete(
        const BodyTrackingSnapshot(
          activeGoal: null,
          goalHistory: [],
          checkIns: [],
        ),
      );
      await load;

      expect(notifications, 1);
    },
  );

  testWidgets(
    'Body screen renders persisted active goal and validation errors',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      await repository.activateGoal(
        kind: BodyGoalKind.cut,
        startWeightKg: 82,
        targetWeightKg: 76,
        startDate: '2026-10-01',
        targetDate: null,
      );
      final model = BodyViewModel(repository);
      await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
      await tester.pumpAndSettle();

      expect(find.text('Gewicht reduzieren'), findsOneWidget);
      expect(find.text('82,0 kg  →  76,0 kg'), findsOneWidget);
      expect(find.byKey(const ValueKey('body-save-goal')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pumpAndSettle();
      // Feldfehler stehen nur an der Zeile, nicht als roher Text auf dem Screen.
      expect(model.errorMessage, isNull);
      expect(model.fieldErrors, contains('weightKg'));
      expect(
        find.textContaining('Das Gewicht muss positiv sein'),
        findsOneWidget,
      );
      expect(
        find.textContaining('BodyTrackingValidationException'),
        findsNothing,
      );
      await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsNothing);
      expect(find.byKey(const ValueKey('body-open-checkin')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('body-open-goal')));
      await tester.pumpAndSettle();
      TextEditingController fieldController(String key) => tester
          .widget<CupertinoTextField>(find.byKey(ValueKey(key)))
          .controller!;
      expect(fieldController('body-start-weight').text, '82,0');
      expect(fieldController('body-target-weight').text, '76,0');
      final unitSegment = find.byKey(const ValueKey('body-goal-weight-unit'));
      await tester.tap(
        find.descendant(of: unitSegment, matching: find.text('lb')),
      );
      await tester.pumpAndSettle();
      expect(fieldController('body-start-weight').text, '180,779055');
      expect(fieldController('body-target-weight').text, '167,551319');
      await tester.tap(
        find.descendant(of: unitSegment, matching: find.text('kg')),
      );
      await tester.pumpAndSettle();
      expect(fieldController('body-start-weight').text, '82,0');
      expect(fieldController('body-target-weight').text, '76,0');
      await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'selecting a prior check-in date pre-fills that day and cancel keeps it',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      final today = DateTime.now();
      final priorDate = today.subtract(const Duration(days: 1));
      String dateOnly(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      String prettyDate(DateTime date) {
        const months = [
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
        ];
        return '${date.day}. ${months[date.month - 1]} ${date.year}';
      }

      await repository.saveCheckIn(
        localDate: dateOnly(priorDate),
        weightKg: 77.2,
        caloriesKcal: 1980,
        proteinGrams: null,
        carbohydrateGrams: null,
        fatGrams: null,
        steps: null,
        sleepMinutes: null,
      );
      final model = BodyViewModel(repository);
      await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();

      final dateRow = find.byKey(const ValueKey('body-checkin-date'));
      final dateRowValue = find.descendant(
        of: dateRow,
        matching: find.text(prettyDate(priorDate)),
      );
      await tester.tap(dateRow);
      await tester.pumpAndSettle();
      final picker = find.byType(CupertinoDatePicker);
      tester.widget<CupertinoDatePicker>(picker).onDateTimeChanged(priorDate);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(dateRowValue, findsOneWidget);
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('body-checkin-weight')),
            )
            .controller
            ?.text,
        '77,2',
      );

      await tester.tap(dateRow);
      await tester.pumpAndSettle();
      final emptyDate = priorDate.subtract(const Duration(days: 1));
      tester.widget<CupertinoDatePicker>(picker).onDateTimeChanged(emptyDate);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: dateRow,
          matching: find.text(prettyDate(emptyDate)),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('body-checkin-weight')),
            )
            .controller
            ?.text,
        isEmpty,
      );

      await tester.tap(dateRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: dateRow,
          matching: find.text(prettyDate(emptyDate)),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('editing another value preserves fractional check-in data', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final today = DateTime.now();
    final localDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await repository.saveCheckIn(
      localDate: localDate,
      weightKg: 77.25,
      caloriesKcal: 1980.5,
      proteinGrams: 148.5,
      carbohydrateGrams: 211.25,
      fatGrams: 62.75,
      steps: 9000,
      sleepMinutes: 450,
    );
    final model = BodyViewModel(repository);
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const ValueKey('body-checkin-weight')),
          )
          .controller
          ?.text,
      '77,25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '77,5',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await repository.read()).checkIns
        .singleWhere((entry) => entry.value.localDate == localDate)
        .value;
    expect(saved.weightKg, 77.5);
    expect(saved.caloriesKcal, 1980.5);
    expect(saved.steps, 9000);
    expect(saved.sleepMinutes, 450);
    expect(saved.proteinGrams, 148.5);
    expect(saved.carbohydrateGrams, 211.25);
    expect(saved.fatGrams, 62.75);
  });

  testWidgets('German comma decimals save as canonical numbers', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final model = BodyViewModel(repository);
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '82,4',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await repository.read()).checkIns.single.value;
    expect(saved.weightKg, 82.4);
    expect(saved.caloriesKcal, isNull);
  });

  testWidgets(
    'body overview remains scrollable at compact width and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final model = BodyViewModel(
        BodyRepository(
          store: LocalSyncStore(database: database, accountId: accountId),
        ),
      );
      await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Verlauf'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-open-checkin')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('body-checkin-weight')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      final layoutError = tester.takeException();
      expect(layoutError, isNull, reason: layoutError?.toStringDeep());
    },
  );

  testWidgets('today summary and history list the saved check-in', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final today = DateTime.now();
    await repository.saveCheckIn(
      localDate: _localDate(today),
      weightKg: 77.2,
      caloriesKcal: 1980,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
      steps: 8000,
      sleepMinutes: null,
    );
    final model = BodyViewModel(repository);
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();

    // Heute-Zeile und Verlaufszeile zeigen dasselbe Gewicht.
    expect(find.text('77,2 kg'), findsNWidgets(2));
    expect(find.text('1.980 kcal'), findsOneWidget);
    expect(find.text('8.000'), findsOneWidget);
    expect(find.text(_prettyDay(today)), findsOneWidget);
    expect(find.text('Verlauf'), findsOneWidget);
  });

  testWidgets('goal sheet saves a target date picked in the date row', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final model = BodyViewModel(repository);
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('body-open-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body-start-weight')),
      '82',
    );
    await tester.enterText(
      find.byKey(const ValueKey('body-target-weight')),
      '76',
    );
    expect(find.text('Kein Datum'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('body-target-date')));
    await tester.pumpAndSettle();
    final target = DateTime.now().add(const Duration(days: 60));
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(target);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.text(_prettyDay(target)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('body-save-goal')));
    await tester.pumpAndSettle();

    final goal = (await repository.read()).activeGoal!.value;
    expect(goal.startWeightKg, closeTo(82, 0.001));
    expect(goal.targetWeightKg, closeTo(76, 0.001));
    expect(goal.targetDate, _localDate(target));
  });

  testWidgets('body sheets size to their content, not the full screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final model = BodyViewModel(
      BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      ),
    );
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();
    final screenHeight = tester.view.physicalSize.height;
    double sheetHeight() => tester
        .getSize(
          find
              .descendant(
                of: find.byType(GainerSheetFrame),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;

    await tester.tap(find.byKey(const ValueKey('body-open-goal')));
    await tester.pumpAndSettle();
    expect(sheetHeight(), lessThan(screenHeight * .8));
    expect(find.text('Sichern'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('body-save-goal'))).height,
      lessThan(60),
    );
    await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
    await tester.pumpAndSettle();
    expect(sheetHeight(), lessThan(screenHeight * .8));
  });

  testWidgets('long pressing the target date removes it', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: accountId),
    );
    final model = BodyViewModel(repository);
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('body-open-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body-start-weight')),
      '82',
    );
    await tester.enterText(
      find.byKey(const ValueKey('body-target-weight')),
      '76',
    );
    final target = DateTime.now().add(const Duration(days: 60));
    await tester.tap(find.byKey(const ValueKey('body-target-date')));
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(target);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.text(_prettyDay(target)), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('body-target-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Datum entfernen'));
    await tester.pumpAndSettle();
    expect(find.text('Kein Datum'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('body-save-goal')));
    await tester.pumpAndSettle();
    final goal = (await repository.read()).activeGoal!.value;
    expect(goal.targetDate, isNull);
  });

  testWidgets(
    'dismissing while a check-in save is pending cannot pop the tab',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final completion = Completer<String>();
      final model = BodyViewModel(
        _DeferredSaveBodyRepository(
          store: LocalSyncStore(database: database, accountId: accountId),
          completion: completion,
        ),
      );
      await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('body-checkin-weight')),
        '82,4',
      );
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pump();
      expect(model.isSaving, isTrue);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsNothing);
      completion.complete('fixture-check-in');
      await tester.pumpAndSettle();

      expect(find.byType(GainerScaffold), findsOneWidget);
      expect(find.text('Check-in'), findsWidgets);
      expect(tester.takeException(), isNull);
      model.dispose();
    },
  );

  testWidgets('a check-in requested by the calendar opens that day', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final model = BodyViewModel(
      BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      ),
    );
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();

    model.requestCheckIn('2026-10-18');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('body-checkin-date')),
        matching: find.text('18. Okt 2026'),
      ),
      findsOneWidget,
    );
    expect(model.requestedCheckInDate, isNull);
  });

  testWidgets('a request made before the screen exists opens on first frame', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final model = BodyViewModel(
      BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      ),
    )..requestCheckIn('2026-10-17');
    await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('body-checkin-date')),
        matching: find.text('17. Okt 2026'),
      ),
      findsOneWidget,
    );
  });
}

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _prettyDay(DateTime date) {
  const months = [
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
  ];
  return '${date.day}. ${months[date.month - 1]} ${date.year}';
}

class _PendingBodyRepository extends BodyRepository {
  _PendingBodyRepository({required super.store, required this.pendingRead});

  final Completer<BodyTrackingSnapshot> pendingRead;

  @override
  Future<BodyTrackingSnapshot> read() => pendingRead.future;
}

class _DeferredSaveBodyRepository extends BodyRepository {
  _DeferredSaveBodyRepository({required super.store, required this.completion});

  final Completer<String> completion;

  @override
  Future<String> saveCheckIn({
    required String localDate,
    required double weightKg,
    double? caloriesKcal,
    double? proteinGrams,
    double? carbohydrateGrams,
    double? fatGrams,
    int? steps,
    int? sleepMinutes,
    int? restingHeartRateBpm,
    int? restingHrvMs,
  }) => completion.future;
}
