import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/check_in_health_coordinator.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/body/body_screen.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';

import '../../support/fake_health_platform.dart';

const _account = '00000000-0000-4000-8000-000000000003';

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime _midnight() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class _Harness {
  _Harness(this.model, this.repository, this.health, this.today);

  final BodyViewModel model;
  final BodyRepository repository;
  final FakeHealthPlatform health;
  final DateTime today;
}

/// Fester Abend, damit Aufstehzeiten nie „in der Zukunft“ liegen.
_Harness _harness(WidgetTester tester, FakeHealthPlatform health) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = BodyRepository(
    store: LocalSyncStore(database: database, accountId: _account),
  );
  final real = DateTime.now();
  final today = DateTime(real.year, real.month, real.day);
  final model = BodyViewModel(
    repository,
    health: CheckInHealthCoordinator(
      platform: health,
      accountId: _account,
      clock: () => today.add(const Duration(hours: 20)),
      onError: (_) {},
    ),
  );
  addTearDown(model.dispose);
  return _Harness(model, repository, health, today);
}

Future<void> _open(
  WidgetTester tester,
  _Harness h, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GainerTheme.forBrightness(brightness),
      home: BodyScreen(viewModel: h.model),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
  await tester.pumpAndSettle();
}

FakeHealthPlatform _healthWithData(DateTime today) => FakeHealthPlatform()
  ..bodyMass = [
    BodyMassSample(
      uuid: 'w1',
      measuredAtUtc: today.add(const Duration(hours: 7)).toUtc(),
      weightKilograms: 81.4,
      sourceName: 'Waage',
    ),
  ]
  ..steps = 8432
  ..sleep = HealthSleepWindow(
    bedtimeUtc: DateTime(
      today.year,
      today.month,
      today.day - 1,
      23,
      10,
    ).toUtc(),
    wakeUtc: DateTime(today.year, today.month, today.day, 6, 45).toUtc(),
    asleepMinutes: 440,
    sourceName: 'Watch',
  );

String _weightText(WidgetTester tester) => tester
    .widget<CupertinoTextField>(
      find.byKey(const ValueKey('body-checkin-weight')),
    )
    .controller!
    .text;

Future<void> _pickTime(
  WidgetTester tester,
  String rowKey,
  int hour,
  int minute,
) async {
  await tester.tap(find.byKey(ValueKey(rowKey)));
  await tester.pumpAndSettle();
  tester
      .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
      .onDateTimeChanged(DateTime(2000, 1, 1, hour, minute));
  await tester.tap(find.text('Fertig'));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('check-in sheet matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      final h = _harness(tester, _healthWithData(_midnight()));
      await _open(tester, h, brightness: brightness);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/body_check_in_sheet_${brightness.name}.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('prefills weight, sleep and steps from Apple Health', (
    tester,
  ) async {
    final h = _harness(tester, _healthWithData(_midnight()));
    await _open(tester, h);

    expect(_weightText(tester), '81,4');
    expect(find.text('Gewicht aus Apple Health'), findsOneWidget);
    expect(find.text('23:10'), findsOneWidget);
    expect(find.text('06:45'), findsOneWidget);
    expect(find.text('7 h 35 min'), findsOneWidget);
    expect(find.text('Schlaf aus Apple Health'), findsOneWidget);
    expect(find.text('8.432'), findsOneWidget);
    expect(find.text('Keine Daten aus Apple Health'), findsNothing);
  });

  testWidgets('new check-in has no calorie or macro fields', (tester) async {
    final h = _harness(tester, FakeHealthPlatform());
    await _open(tester, h);

    expect(find.byType(CupertinoTextField), findsOneWidget);
    for (final label in ['Kalorien', 'Protein', 'Kohlenhydrate', 'Fett']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('Zu Bett'), findsOneWidget);
    expect(find.text('Aufgestanden'), findsOneWidget);
  });

  testWidgets('steps show a hint without Health data and stay empty', (
    tester,
  ) async {
    final h = _harness(tester, FakeHealthPlatform());
    await _open(tester, h);

    expect(find.text('Keine Daten aus Apple Health'), findsOneWidget);
    expect(find.text('Nicht gesetzt'), findsNWidgets(2));
    expect(find.text('Gewicht aus Apple Health'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80,9',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();
    final saved = (await h.repository.read()).checkIns.single.value;
    expect(saved.steps, isNull);
    expect(saved.sleepMinutes, isNull);
  });

  testWidgets('manual sleep across midnight saves 450 minutes', (tester) async {
    final h = _harness(tester, FakeHealthPlatform());
    await _open(tester, h);

    await _pickTime(tester, 'body-checkin-bedtime', 23, 30);
    expect(find.text('Dauer'), findsOneWidget);
    expect(find.text('–'), findsOneWidget);
    await _pickTime(tester, 'body-checkin-wake', 7, 0);
    expect(find.text('7 h 30 min'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80,9',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await h.repository.read()).checkIns.single.value;
    expect(saved.sleepMinutes, 450);
    final write = h.health.sleepWrites.single;
    expect(
      write.bed,
      DateTime(h.today.year, h.today.month, h.today.day - 1, 23, 30).toUtc(),
    );
    expect(
      write.wake,
      DateTime(h.today.year, h.today.month, h.today.day, 7).toUtc(),
    );
    expect(write.id, endsWith('-${_localDate(h.today)}-sleep'));
  });

  testWidgets('saving writes weight to Health when no foreign sample exists', (
    tester,
  ) async {
    final h = _harness(tester, FakeHealthPlatform());
    await _open(tester, h);
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80,9',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    expect(h.health.bodyMassWrites.single.kg, 80.9);
    expect(h.health.sleepWrites, isEmpty);
    expect(find.byKey(const ValueKey('body-save-checkin')), findsNothing);
  });

  testWidgets('saving does not write over foreign Health samples', (
    tester,
  ) async {
    final h = _harness(tester, _healthWithData(_midnight()));
    await _open(tester, h);
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '82',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await h.repository.read()).checkIns.single.value;
    expect(saved.weightKg, 82);
    expect(saved.steps, 8432);
    expect(saved.sleepMinutes, 455);
    expect(h.health.bodyMassWrites, isEmpty);
    expect(h.health.sleepWrites, isEmpty);
  });

  testWidgets('Health errors never block saving the check-in', (tester) async {
    final health = FakeHealthPlatform()
      ..checkInAuthorizationError = StateError('denied')
      ..writeError = StateError('write denied');
    final h = _harness(tester, health);
    await _open(tester, h);
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    expect(h.model.errorMessage, isNull);
    expect((await h.repository.read()).checkIns.single.value.weightKg, 80);
    expect(find.byKey(const ValueKey('body-save-checkin')), findsNothing);
  });

  testWidgets('changing the date reloads the Health values', (tester) async {
    final h = _harness(tester, _healthWithData(_midnight()));
    await _open(tester, h);
    expect(find.text('23:10'), findsOneWidget);

    final yesterday = h.today.subtract(const Duration(days: 1));
    await tester.tap(find.byKey(const ValueKey('body-checkin-date')));
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
        .onDateTimeChanged(yesterday);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    expect(h.health.stepReads, hasLength(2));
    expect(
      h.health.stepReads.last.from,
      DateTime(yesterday.year, yesterday.month, yesterday.day).toUtc(),
    );
  });
}
