import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/health/check_in_health_coordinator.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/body/body_screen.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/body/check_in_format.dart';

import '../../support/fake_health_platform.dart';

const _account = '00000000-0000-4000-8000-000000000003';

String _localDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Fester Tag ohne Zeitumstellung, damit die Tests nicht vom Ausführungstag
/// abhängen.
final _day = DateTime(2026, 10, 12);

/// Nächte der Zeitumstellung in Europa (Herbst 2026, Frühling 2027).
final _autumnDay = DateTime(2026, 10, 25);
final _springDay = DateTime(2027, 3, 28);

class _Harness {
  _Harness(this.model, this.repository, this.health, this.today);

  final BodyViewModel model;
  final BodyRepository repository;
  final FakeHealthPlatform health;
  final DateTime today;

  /// Fester Abend, damit Aufstehzeiten nie „in der Zukunft“ liegen.
  DateTime now() => DateTime(today.year, today.month, today.day, 20);
}

_Harness _harness(
  WidgetTester tester,
  FakeHealthPlatform health, {
  DateTime? today,
}) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = BodyRepository(
    store: LocalSyncStore(database: database, accountId: _account),
  );
  final day = today ?? _day;
  final clock = DateTime(day.year, day.month, day.day, 20);
  final model = BodyViewModel(
    repository,
    health: CheckInHealthCoordinator(
      platform: health,
      accountId: _account,
      clock: () => clock,
      onError: (_) {},
    ),
  );
  addTearDown(model.dispose);
  return _Harness(model, repository, health, day);
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
      home: BodyScreen(viewModel: h.model, clock: h.now),
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
      measuredAtUtc: DateTime(today.year, today.month, today.day, 7).toUtc(),
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
      final h = _harness(tester, _healthWithData(_day));
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
    final h = _harness(tester, _healthWithData(_day));
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

  // Unter TZ=Europe/Berlin liegen 510 (Herbst) bzw. 390 (Frühling) echte
  // Minuten zwischen 23:30 und 07:00; unter UTC 450. Die Schlafenszeit in
  // Health bleibt in jedem Fall 23:30 Uhr am Vortag.
  for (final (name, day) in [('autumn', _autumnDay), ('spring', _springDay)]) {
    testWidgets('manual sleep in the $name DST night keeps 23:30 as bedtime', (
      tester,
    ) async {
      final h = _harness(tester, FakeHealthPlatform(), today: day);
      await _open(tester, h);
      final bedtime = DateTime(day.year, day.month, day.day - 1, 23, 30);
      final wake = DateTime(day.year, day.month, day.day, 7);
      final realMinutes = wake.difference(bedtime).inMinutes;

      await _pickTime(tester, 'body-checkin-bedtime', 23, 30);
      await _pickTime(tester, 'body-checkin-wake', 7, 0);
      expect(find.text(formatSleepDuration(realMinutes)), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('body-checkin-weight')),
        '80,9',
      );
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pumpAndSettle();

      final saved = (await h.repository.read()).checkIns.single.value;
      expect(saved.localDate, _localDate(day));
      expect(saved.sleepMinutes, realMinutes);
      final write = h.health.sleepWrites.single;
      expect(write.bed, bedtime.toUtc());
      expect(write.wake, wake.toUtc());
      expect(write.bed.toLocal().hour, 23);
      expect(write.bed.toLocal().minute, 30);
      expect(write.wake.difference(write.bed).inMinutes, saved.sleepMinutes);
    });

    testWidgets('Health sleep in the $name DST night keeps its duration', (
      tester,
    ) async {
      final bedtime = DateTime(day.year, day.month, day.day - 1, 23, 30);
      final wake = DateTime(day.year, day.month, day.day, 7);
      final realMinutes = wake.difference(bedtime).inMinutes;
      final health = FakeHealthPlatform()
        ..sleep = HealthSleepWindow(
          bedtimeUtc: bedtime.toUtc(),
          wakeUtc: wake.toUtc(),
          asleepMinutes: realMinutes - 20,
          sourceName: 'Watch',
        );
      final h = _harness(tester, health, today: day);
      await _open(tester, h);

      expect(find.text('23:30'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text(formatSleepDuration(realMinutes)), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('body-checkin-weight')),
        '80,9',
      );
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pumpAndSettle();

      final saved = (await h.repository.read()).checkIns.single.value;
      expect(saved.sleepMinutes, realMinutes);
      expect(h.health.sleepWrites, isEmpty);
    });
  }

  testWidgets('a 24.5 h autumn night is saved as at most 24 h', (tester) async {
    final h = _harness(tester, FakeHealthPlatform(), today: _autumnDay);
    await _open(tester, h);
    final bedtime = DateTime(2026, 10, 24, 7, 30);
    final wake = DateTime(2026, 10, 25, 7);
    final real = wake.difference(bedtime).inMinutes;
    final expected = real > maxSleepMinutes ? maxSleepMinutes : real;

    await _pickTime(tester, 'body-checkin-bedtime', 7, 30);
    await _pickTime(tester, 'body-checkin-wake', 7, 0);
    expect(find.text(formatSleepDuration(expected)), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80,9',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    expect(h.model.fieldErrors, isEmpty);
    final saved = (await h.repository.read()).checkIns.single.value;
    expect(saved.sleepMinutes, expected);
    final write = h.health.sleepWrites.single;
    expect(write.bed, bedtime.toUtc());
    expect(write.wake, wake.toUtc());
  });

  testWidgets('Health sleep in the repeated autumn hour keeps its instants', (
    tester,
  ) async {
    // 01:30Z ist unter TZ=Europe/Berlin 02:30 Uhr in der zweiten, doppelten
    // Stunde (MEZ). Aus der Uhrzeit zurückgerechnet würde daraus 02:30 MESZ,
    // eine Stunde früher.
    final bedtimeUtc = DateTime.utc(2026, 10, 25, 1, 30);
    final wakeUtc = DateTime.utc(2026, 10, 25, 6);
    final health = FakeHealthPlatform()
      ..sleep = HealthSleepWindow(
        bedtimeUtc: bedtimeUtc,
        wakeUtc: wakeUtc,
        asleepMinutes: 250,
        sourceName: 'Gainer',
        fromGainer: true,
      );
    final h = _harness(tester, health, today: _autumnDay);
    await _open(tester, h);

    final bed = bedtimeUtc.toLocal(), wake = wakeUtc.toLocal();
    expect(
      find.text(formatMinuteOfDay(bed.hour * 60 + bed.minute)),
      findsOneWidget,
    );
    expect(
      find.text(formatMinuteOfDay(wake.hour * 60 + wake.minute)),
      findsOneWidget,
    );
    expect(find.text(formatSleepDuration(270)), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('body-checkin-weight')),
      '80,9',
    );
    await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
    await tester.pumpAndSettle();

    final saved = (await h.repository.read()).checkIns.single.value;
    expect(saved.sleepMinutes, 270);
    final write = h.health.sleepWrites.single;
    expect(write.bed, bedtimeUtc);
    expect(write.wake, wakeUtc);
  });

  testWidgets('a bedtime in the skipped spring hour blocks saving', (
    tester,
  ) async {
    final h = _harness(tester, FakeHealthPlatform(), today: _springDay);
    await _open(tester, h);
    await _pickTime(tester, 'body-checkin-bedtime', 2, 30);
    await _pickTime(tester, 'body-checkin-wake', 3, 10);

    // 02:30 gibt es am 28.03.2027 in Europe/Berlin nicht (Dart: 03:30, also
    // nach 03:10). Unter UTC ist es eine gültige Nacht von 40 Minuten.
    final skipped = DateTime(
      2027,
      3,
      28,
      2,
      30,
    ).isAfter(DateTime(2027, 3, 28, 3, 10));
    final save = tester.widget<GainerPillButton>(
      find.byKey(const ValueKey('body-save-checkin')),
    );
    if (skipped) {
      expect(
        find.text(
          'Diese Uhrzeit gibt es in der Nacht der Zeitumstellung nicht.',
        ),
        findsOneWidget,
      );
      expect(save.onPressed, isNull);
      expect(find.text('–'), findsOneWidget);
    } else {
      expect(save.onPressed, isNotNull);
      expect(find.text('40 min'), findsOneWidget);
    }
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
    final h = _harness(tester, _healthWithData(_day));
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
    final h = _harness(tester, _healthWithData(_day));
    await _open(tester, h);
    expect(find.text('23:10'), findsOneWidget);

    final yesterday = DateTime(h.today.year, h.today.month, h.today.day - 1);
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
