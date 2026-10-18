import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/timer/rest_timer_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_shortcuts.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
const otherAccountId = '00000000-0000-4000-8000-000000000002';
const workoutId = '00000000-0000-4000-8000-000000000010';
final t0 = DateTime.utc(2026, 10, 17, 10);

void main() {
  late LocalDatabase database;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  RestTimerStore storeFor(String account) => RestTimerStore(
    store: LocalSyncStore(database: database, accountId: account),
  );

  group('Timer laden und speichern', () {
    test(
      'ohne gespeicherten Zustand liefert ein Bereit-Timer mit 3:00',
      () async {
        final timer = await storeFor(accountId).load(workoutId, now: t0);
        expect(timer.phase, RestTimerPhase.ready);
        expect(timer.remainingSecondsAt(t0), 180);
      },
    );

    test('Rückkehr aus dem Hintergrund zeigt 2:30 nach 30 s', () async {
      final running = RestTimerState.ready(workoutId: workoutId).start(now: t0);
      expect(await storeFor(accountId).save(running), isTrue);

      final timer = await storeFor(accountId)
          .load(workoutId, now: t0.add(const Duration(seconds: 30)));
      expect(timer.phase, RestTimerPhase.running);
      expect(
        timer.remainingSecondsAt(t0.add(const Duration(seconds: 30))),
        150,
      );
    });

    test(
      'Prozessende während Pause liefert die gespeicherte Restzeit',
      () async {
        final paused = RestTimerState.ready(workoutId: workoutId)
            .start(now: t0)
            .stop(now: t0.add(const Duration(seconds: 10)));
        await storeFor(accountId).save(paused);

        final restarted = storeFor(accountId);
        final timer = await restarted.load(
          workoutId,
          now: t0.add(const Duration(minutes: 30)),
        );
        expect(timer.phase, RestTimerPhase.paused);
        expect(timer.pausedRemainingSeconds, 170);
      },
    );

    test('laufender Timer mit Zielzeit in der Vergangenheit wird als expired geladen', () async {
      final running = RestTimerState.ready(
        workoutId: workoutId,
        baseDurationSeconds: 60,
      ).start(now: t0);
      await storeFor(accountId).save(running);

      final timer = await storeFor(accountId)
          .load(workoutId, now: t0.add(const Duration(seconds: 61)));
      expect(timer.phase, RestTimerPhase.expired);
      expect(timer.remainingSecondsAt(t0), 0);
    });

    test('Laden ist deterministisch und schreibt nicht', () async {
      final running = RestTimerState.ready(
        workoutId: workoutId,
        baseDurationSeconds: 60,
      ).start(now: t0);
      await storeFor(accountId).save(running);
      final later = t0.add(const Duration(seconds: 61));

      final first = await storeFor(accountId).load(workoutId, now: later);
      final second = await storeFor(accountId).load(workoutId, now: later);
      expect(second.phase, first.phase);
      expect(second.generation, first.generation);
    });

    test('Timeraktionen erzeugen keine Outbox-Mutation', () async {
      await storeFor(accountId)
          .save(RestTimerState.ready(workoutId: workoutId).start(now: t0));
      final outbox = await LocalSyncStore(
        database: database,
        accountId: accountId,
      ).readOutbox();
      expect(outbox, isEmpty);
    });
  });

  group('Generation', () {
    test('veraltete Generation wird verworfen', () async {
      final store = storeFor(accountId);
      final ready = RestTimerState.ready(workoutId: workoutId);
      final v1 = ready.start(now: t0);
      final v2 = v1.stop(now: t0);
      final v3 = v2.start(now: t0);

      expect(await store.save(v1), isTrue);
      expect(await store.save(v3), isTrue);
      expect(await store.save(v2), isFalse);

      final loaded = await store.load(workoutId, now: t0);
      expect(loaded.phase, RestTimerPhase.running);
      expect(loaded.generation, v3.generation);
    });

    test('gleiche Generation wird ebenfalls verworfen', () async {
      final store = storeFor(accountId);
      final running = RestTimerState.ready(workoutId: workoutId).start(now: t0);
      expect(await store.save(running), isTrue);
      expect(await store.save(running), isFalse);
    });
  });

  group('Shortcuts', () {
    test('ohne Speicherung gelten Standard 1:00, 2:00, 3:00', () async {
      final shortcuts = await storeFor(accountId).loadShortcuts();
      expect(shortcuts.seconds, [60, 120, 180]);
    });

    test('hinzufügen, löschen und Speicherung über Neustart', () async {
      final store = storeFor(accountId);
      final shortcuts = (await store.loadShortcuts())
          .add(150)
          .remove(60)
          .move(2, 0);
      await store.saveShortcuts(shortcuts);

      final restarted = await storeFor(accountId).loadShortcuts();
      expect(restarted.seconds, [150, 120, 180]);
    });

    test(
      'leere Liste bleibt leer und wird nicht durch Standard ersetzt',
      () async {
        final store = storeFor(accountId);
        await store.saveShortcuts(RestTimerShortcuts.fromSeconds([]));
        expect((await store.loadShortcuts()).seconds, isEmpty);
      },
    );
  });

  group('Kontotrennung', () {
    test(
      'Timer und Shortcuts eines anderen Kontos sind nicht lesbar',
      () async {
        final owner = storeFor(accountId);
        await owner.save(
          RestTimerState.ready(workoutId: workoutId).start(now: t0),
        );
        await owner.saveShortcuts(RestTimerShortcuts.fromSeconds([45]));

        final other = storeFor(otherAccountId);
        await expectLater(
          other.load(workoutId, now: t0),
          throwsA(isA<StateError>()),
        );
        await expectLater(other.loadShortcuts(), throwsA(isA<StateError>()));
        await expectLater(
          other.save(RestTimerState.ready(workoutId: workoutId, generation: 9)),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
