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
    });
  }

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
      expect(find.text('82.0 kg  →  76.0 kg'), findsOneWidget);
      expect(find.byKey(const ValueKey('body-save-goal')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pumpAndSettle();
      expect(model.errorMessage, isNotNull);
      expect(
        find.textContaining('Das Gewicht muss positiv sein'),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('body-save-checkin')), findsNothing);
      expect(find.byKey(const ValueKey('body-open-checkin')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('body-open-goal')));
      await tester.pumpAndSettle();
      TextEditingController fieldController(String key) => tester
          .widget<CupertinoTextField>(find.byKey(ValueKey(key)))
          .controller!;
      expect(fieldController('body-start-weight').text, '82.0');
      expect(fieldController('body-target-weight').text, '76.0');
      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();
      expect(fieldController('body-start-weight').text, '180.779055');
      expect(fieldController('body-target-weight').text, '167.551319');
      await tester.tap(find.text('kg'));
      await tester.pumpAndSettle();
      expect(fieldController('body-start-weight').text, '82.0');
      expect(fieldController('body-target-weight').text, '76.0');
      await tester.tap(find.text('Abbrechen'));
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

      await tester.tap(find.byKey(const ValueKey('body-checkin-date')));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('body-checkin-date-wheel'));
      tester.widget<CupertinoDatePicker>(picker).onDateTimeChanged(priorDate);
      await tester.tap(find.byKey(const ValueKey('body-checkin-date-done')));
      await tester.pumpAndSettle();
      expect(
        find.text('Check-in für ${prettyDate(priorDate)}'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField).at(1))
            .controller
            ?.text,
        '1980',
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('body-checkin-weight')),
            )
            .controller
            ?.text,
        '77.2',
      );

      await tester.tap(find.byKey(const ValueKey('body-checkin-date')));
      await tester.pumpAndSettle();
      final emptyDate = priorDate.subtract(const Duration(days: 1));
      tester.widget<CupertinoDatePicker>(picker).onDateTimeChanged(emptyDate);
      await tester.tap(find.byKey(const ValueKey('body-checkin-date-done')));
      await tester.pumpAndSettle();
      expect(
        find.text('Check-in für ${prettyDate(emptyDate)}'),
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

      await tester.tap(find.byKey(const ValueKey('body-checkin-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Check-in für ${prettyDate(emptyDate)}'),
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
      '77.25',
    );
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).at(2))
          .controller
          ?.text,
      '148.5',
    );
    await tester.enterText(find.byType(CupertinoTextField).at(1), '1990');
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await repository.read()).checkIns
        .singleWhere((entry) => entry.value.localDate == localDate)
        .value;
    expect(saved.weightKg, 77.25);
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
    await tester.enterText(find.byType(CupertinoTextField).at(2), '148,5');
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await repository.read()).checkIns.single.value;
    expect(saved.weightKg, 82.4);
    expect(saved.proteinGrams, 148.5);
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
        find.byKey(const ValueKey('body-open-checkin')),
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
        '82.4',
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
    required double? caloriesKcal,
    required double? proteinGrams,
    required double? carbohydrateGrams,
    required double? fatGrams,
    required int? steps,
    required int? sleepMinutes,
  }) => completion.future;
}
