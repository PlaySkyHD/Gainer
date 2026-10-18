import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/health/check_in_health_coordinator.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';

import '../../support/fake_health_platform.dart';

const _account = 'acc-1';

BodyMassSample _weight(
  DateTime at,
  double kg, {
  String source = 'Waage',
  String? syncId,
}) => BodyMassSample(
  uuid: 'u-${at.millisecondsSinceEpoch}',
  measuredAtUtc: at.toUtc(),
  weightKilograms: kg,
  sourceName: source,
  syncIdentifier: syncId,
);

HealthSleepWindow _sleep(
  DateTime bed,
  DateTime wake, {
  bool fromGainer = false,
}) => HealthSleepWindow(
  bedtimeUtc: bed.toUtc(),
  wakeUtc: wake.toUtc(),
  asleepMinutes: wake.difference(bed).inMinutes,
  sourceName: fromGainer ? 'Gainer' : 'Watch',
  fromGainer: fromGainer,
);

CheckInHealthCoordinator _coordinator(
  FakeHealthPlatform platform,
  DateTime now, {
  List<Object>? errors,
}) => CheckInHealthCoordinator(
  platform: platform,
  accountId: _account,
  clock: () => now,
  onError: (error) => errors?.add(error),
);

void main() {
  group('Zeitfenster', () {
    test(
      'vergangener Tag: Mitternacht bis Mitternacht, Nacht 18:00 bis 14:00',
      () {
        final coordinator = _coordinator(
          FakeHealthPlatform(),
          DateTime(2026, 10, 18, 15, 30),
        );
        final day = coordinator.dayWindow('2026-10-16')!;
        expect(day.from, DateTime(2026, 10, 16).toUtc());
        expect(day.to, DateTime(2026, 10, 17).toUtc());
        final night = coordinator.nightWindow('2026-10-16')!;
        expect(night.from, DateTime(2026, 10, 15, 18).toUtc());
        expect(night.to, DateTime(2026, 10, 16, 14).toUtc());
      },
    );

    test(
      'heute endet der Tag jetzt, die Nacht nach 14:00 weiterhin um 14:00',
      () {
        final now = DateTime(2026, 10, 18, 15, 30);
        final coordinator = _coordinator(FakeHealthPlatform(), now);
        expect(coordinator.dayWindow('2026-10-18')!.to, now.toUtc());
        expect(
          coordinator.nightWindow('2026-10-18')!.to,
          DateTime(2026, 10, 18, 14).toUtc(),
        );
      },
    );

    test('morgens wird auch die Nacht auf jetzt begrenzt', () {
      final now = DateTime(2026, 10, 18, 7, 5);
      final night = _coordinator(
        FakeHealthPlatform(),
        now,
      ).nightWindow('2026-10-18')!;
      expect(night.from, DateTime(2026, 10, 17, 18).toUtc());
      expect(night.to, now.toUtc());
    });

    test('kurz nach Mitternacht reicht die Nacht über den Tageswechsel', () {
      final now = DateTime(2026, 10, 18, 0, 30);
      final coordinator = _coordinator(FakeHealthPlatform(), now);
      final day = coordinator.dayWindow('2026-10-18')!;
      expect(day.from, DateTime(2026, 10, 18).toUtc());
      expect(day.to, now.toUtc());
      expect(
        coordinator.nightWindow('2026-10-18')!.from,
        DateTime(2026, 10, 17, 18).toUtc(),
      );
    });

    test('Tage in der Zukunft haben kein Fenster', () {
      final coordinator = _coordinator(
        FakeHealthPlatform(),
        DateTime(2026, 10, 18, 12),
      );
      expect(coordinator.dayWindow('2026-10-19'), isNull);
      expect(coordinator.nightWindow('2026-10-19'), isNull);
    });
  });

  group('Lesen', () {
    final now = DateTime(2026, 10, 18, 15, 30);

    test('liefert jüngstes Gewicht, Schritte und Schlaf', () async {
      final platform = FakeHealthPlatform()
        ..bodyMass = [
          _weight(DateTime(2026, 10, 18, 7), 81.0),
          _weight(DateTime(2026, 10, 18, 12), 81.4),
        ]
        ..steps = 8432
        ..sleep = _sleep(
          DateTime(2026, 10, 17, 23, 10),
          DateTime(2026, 10, 18, 6, 45),
        );
      final snapshot = await _coordinator(platform, now).load('2026-10-18');

      expect(platform.checkInAuthorizations, 1);
      expect(snapshot.weightKg, 81.4);
      expect(snapshot.weightChecked, isTrue);
      expect(snapshot.hasForeignWeight, isTrue);
      expect(snapshot.steps, 8432);
      expect(snapshot.sleep!.asleepMinutes, 455);
      expect(snapshot.hasForeignSleep, isTrue);
      expect(platform.bodyMassReads.single.to, now.toUtc());
      expect(
        platform.sleepReads.single.from,
        DateTime(2026, 10, 17, 18).toUtc(),
      );
    });

    test('eigene Gainer-Proben zählen nicht als fremd', () async {
      final platform = FakeHealthPlatform()
        ..bodyMass = [
          _weight(
            DateTime(2026, 10, 18, 9),
            80.9,
            source: 'Gainer',
            syncId: 'gainer-checkin-acc-1-2026-10-18-weight',
          ),
          _weight(DateTime(2026, 10, 18, 10), 80.5, syncId: 'gainer-checkin-x'),
        ]
        ..sleep = _sleep(
          DateTime(2026, 10, 17, 23),
          DateTime(2026, 10, 18, 7),
          fromGainer: true,
        );
      final snapshot = await _coordinator(platform, now).load('2026-10-18');

      expect(snapshot.weightKg, 80.5);
      expect(snapshot.hasForeignWeight, isFalse);
      expect(snapshot.hasForeignSleep, isFalse);
      expect(snapshot.sleep, isNotNull);
    });

    test(
      'Proben außerhalb des Tages und ungültige Werte werden ignoriert',
      () async {
        final platform = FakeHealthPlatform()
          ..bodyMass = [
            _weight(DateTime(2026, 10, 17, 23, 59), 90),
            _weight(DateTime(2026, 10, 18, 8), double.nan),
            _weight(DateTime(2026, 10, 18, 9), 0),
          ]
          ..steps = 0;
        final snapshot = await _coordinator(platform, now).load('2026-10-18');
        expect(snapshot.weightKg, isNull);
        expect(snapshot.weightChecked, isTrue);
        expect(snapshot.hasForeignWeight, isFalse);
        expect(snapshot.steps, isNull);
      },
    );

    test('verweigerte oder fehlerhafte Berechtigung wirft nicht', () async {
      final errors = <Object>[];
      final platform = FakeHealthPlatform()
        ..checkInAuthorizationError = StateError('denied')
        ..steps = 100;
      final snapshot = await _coordinator(
        platform,
        now,
        errors: errors,
      ).load('2026-10-18');
      expect(snapshot.weightChecked, isFalse);
      expect(snapshot.steps, isNull);
      expect(platform.stepReads, isEmpty);
      expect(errors, hasLength(1));
    });

    test('nicht verfügbares Health liefert leere Werte ohne Anfrage', () async {
      final platform = FakeHealthPlatform()..available = false;
      final snapshot = await _coordinator(platform, now).load('2026-10-18');
      expect(snapshot.weightKg, isNull);
      expect(platform.checkInAuthorizations, 0);
    });

    test('Lesefehler lassen den Snapshot ungeprüft', () async {
      final errors = <Object>[];
      final platform = FakeHealthPlatform()..readError = StateError('boom');
      final snapshot = await _coordinator(
        platform,
        now,
        errors: errors,
      ).load('2026-10-18');
      expect(snapshot.weightChecked, isFalse);
      expect(snapshot.sleepChecked, isFalse);
      expect(errors, hasLength(3));
    });

    test('Tage in der Zukunft lesen nichts', () async {
      final platform = FakeHealthPlatform()..steps = 5;
      final snapshot = await _coordinator(platform, now).load('2026-10-20');
      expect(snapshot.steps, isNull);
      expect(platform.stepReads, isEmpty);
      expect(platform.sleepReads, isEmpty);
    });
  });

  group('Schreiben', () {
    final now = DateTime(2026, 10, 18, 15, 30);
    final bed = DateTime(2026, 10, 17, 23, 30);
    final wake = DateTime(2026, 10, 18, 7);

    test('schreibt Gewicht und Schlaf ohne fremde Probe', () async {
      final platform = FakeHealthPlatform();
      final coordinator = _coordinator(platform, now);
      final snapshot = await coordinator.load('2026-10-18');

      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 80.9,
        bedtime: bed,
        wake: wake,
      );

      expect(platform.bodyMassWrites.single.kg, 80.9);
      expect(platform.bodyMassWrites.single.at, now.toUtc());
      expect(
        platform.bodyMassWrites.single.id,
        'gainer-checkin-acc-1-2026-10-18-weight',
      );
      expect(platform.sleepWrites.single.bed, bed.toUtc());
      expect(platform.sleepWrites.single.wake, wake.toUtc());
      expect(
        platform.sleepWrites.single.id,
        'gainer-checkin-acc-1-2026-10-18-sleep',
      );
    });

    test('frühere Tage schreiben das Gewicht mittags', () async {
      final platform = FakeHealthPlatform();
      final coordinator = _coordinator(platform, now);
      final snapshot = await coordinator.load('2026-10-16');
      await coordinator.writeBack(
        localDate: '2026-10-16',
        snapshot: snapshot,
        weightKg: 80,
      );
      expect(
        platform.bodyMassWrites.single.at,
        DateTime(2026, 10, 16, 12).toUtc(),
      );
      expect(platform.sleepWrites, isEmpty);
    });

    test('korrigiertes Gewicht nutzt dieselbe syncIdentifier', () async {
      final platform = FakeHealthPlatform();
      final coordinator = _coordinator(platform, now);
      final snapshot = await coordinator.load('2026-10-18');
      for (final kg in [80.9, 81.0]) {
        await coordinator.writeBack(
          localDate: '2026-10-18',
          snapshot: snapshot,
          weightKg: kg,
        );
      }
      expect(platform.bodyMassWrites.map((w) => w.id).toSet(), hasLength(1));
      expect(platform.bodyMassWrites.last.kg, 81.0);
    });

    test('fremde Proben werden nicht überschrieben', () async {
      final platform = FakeHealthPlatform()
        ..bodyMass = [_weight(DateTime(2026, 10, 18, 7), 81.4)]
        ..sleep = _sleep(DateTime(2026, 10, 17, 23), DateTime(2026, 10, 18, 7));
      final coordinator = _coordinator(platform, now);
      final snapshot = await coordinator.load('2026-10-18');
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 82,
        bedtime: bed,
        wake: wake,
      );
      expect(platform.bodyMassWrites, isEmpty);
      expect(platform.sleepWrites, isEmpty);
    });

    test('eigene Proben werden ersetzt', () async {
      final platform = FakeHealthPlatform()
        ..bodyMass = [
          _weight(
            DateTime(2026, 10, 18, 7),
            81.4,
            source: 'Gainer',
            syncId: 'gainer-checkin-acc-1-2026-10-18-weight',
          ),
        ]
        ..sleep = _sleep(bed, wake, fromGainer: true);
      final coordinator = _coordinator(platform, now);
      final snapshot = await coordinator.load('2026-10-18');
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 81.0,
        bedtime: bed,
        wake: wake,
      );
      expect(platform.bodyMassWrites, hasLength(1));
      expect(platform.sleepWrites, hasLength(1));
    });

    test('ohne erfolgreiches Lesen wird nichts geschrieben', () async {
      final platform = FakeHealthPlatform();
      final coordinator = _coordinator(platform, now);
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: CheckInHealthSnapshot.empty,
        weightKg: 80,
        bedtime: bed,
        wake: wake,
      );
      expect(platform.bodyMassWrites, isEmpty);
      expect(platform.sleepWrites, isEmpty);
    });

    test('Aufstehzeit in der Zukunft wird nicht geschrieben', () async {
      final platform = FakeHealthPlatform();
      final early = DateTime(2026, 10, 18, 6);
      final coordinator = _coordinator(platform, early);
      final snapshot = await coordinator.load('2026-10-18');
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 80,
        bedtime: DateTime(2026, 10, 17, 23),
        wake: DateTime(2026, 10, 18, 7),
      );
      expect(platform.sleepWrites, isEmpty);
      expect(platform.bodyMassWrites, hasLength(1));
    });

    test('Schreibfehler und fehlende Berechtigung werfen nicht', () async {
      final errors = <Object>[];
      final platform = FakeHealthPlatform()
        ..writeResult = HealthWriteStatus.notAuthorized;
      final coordinator = _coordinator(platform, now, errors: errors);
      final snapshot = await coordinator.load('2026-10-18');
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 80,
        bedtime: bed,
        wake: wake,
      );
      expect(errors, isEmpty);

      platform.writeError = StateError('save failed');
      await coordinator.writeBack(
        localDate: '2026-10-18',
        snapshot: snapshot,
        weightKg: 80,
        bedtime: bed,
        wake: wake,
      );
      expect(errors, hasLength(2));
    });
  });
}
