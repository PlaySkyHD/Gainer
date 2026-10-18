import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_shortcuts.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';

const workoutId = '00000000-0000-4000-8000-000000000010';
final t0 = DateTime.utc(2026, 10, 17, 10);

RestTimerState ready([int seconds = 180]) =>
    RestTimerState.ready(workoutId: workoutId, baseDurationSeconds: seconds);

void main() {
  group('Pausentimer nur manuell starten', () {
    test('Satz erfasst ohne Timeraktion startet keinen Timer', () {
      final state = ready();
      expect(state.acknowledgeNextSetRecorded(), same(state));
      expect(state.expire(now: t0.add(const Duration(hours: 1))), same(state));
      expect(state.phase, RestTimerPhase.ready);
    });

    test('Timeransicht öffnen zeigt 3:00 im Bereit-Zustand', () {
      final state = ready();
      expect(state.phase, RestTimerPhase.ready);
      expect(state.remainingSecondsAt(t0), 180);
      expect(state.baseDurationSeconds, 180);
    });
  });

  group('Dauer wählen und Shortcuts', () {
    test('Shortcut 2:30 startet einen Timer mit 2:30', () {
      final state = ready().selectShortcut(150, now: t0).start(now: t0);
      expect(state.phase, RestTimerPhase.running);
      expect(state.remainingSecondsAt(t0), 150);
    });

    test('+15 s bei 0:40 ergibt 0:55 und neues Ende', () {
      final started = ready(40).start(now: t0);
      final adjusted = started.adjust(15, now: t0);
      expect(adjusted.remainingSecondsAt(t0), 55);
      expect(adjusted.targetAtUtc, t0.add(const Duration(seconds: 55)));
      expect(adjusted.generation, greaterThan(started.generation));
    });

    test('Ausgangsdauer bleibt beim Laufen unverändert', () {
      final adjusted = ready(40).start(now: t0).adjust(15, now: t0);
      expect(adjusted.baseDurationSeconds, 40);
    });

    test('Bereit-Dauer ±15 s wird auf 5 s bis 30 min begrenzt', () {
      expect(ready(10).adjust(-15, now: t0).baseDurationSeconds, 5);
      expect(ready(1800).adjust(15, now: t0).baseDurationSeconds, 1800);
      final max = ready(1800);
      expect(max.adjust(15, now: t0), same(max));
    });

    test('Laufende Restzeit wird nicht über 30 min verlängert', () {
      final state = ready(1800).start(now: t0).adjust(15, now: t0);
      expect(state.remainingSecondsAt(t0), 1800);
    });

    test('Restzeit wird nie negativ, ±15 s auf null läuft ab', () {
      final state = ready(10).start(now: t0).adjust(-15, now: t0);
      expect(state.phase, RestTimerPhase.expired);
      expect(state.remainingSecondsAt(t0), 0);
    });

    test('Shortcut ist während Lauf oder Pause nicht erlaubt', () {
      final running = ready().start(now: t0);
      expect(
        () => running.selectShortcut(60, now: t0),
        throwsA(isA<RestTimerException>()),
      );
      final paused = running.stop(now: t0);
      expect(
        () => paused.selectShortcut(60, now: t0),
        throwsA(isA<RestTimerException>()),
      );
    });

    test('Shortcut aus Bereit und abgelaufen setzt die Dauer', () {
      final fromExpired = ready(60)
          .start(now: t0)
          .expire(now: t0.add(const Duration(seconds: 60)))
          .selectShortcut(120, now: t0);
      expect(fromExpired.phase, RestTimerPhase.ready);
      expect(fromExpired.baseDurationSeconds, 120);
    });
  });

  group('Stop pausiert, Start setzt fort', () {
    test('Stop bei 1:10, 30 s warten, Start läuft mit 1:10 weiter', () {
      final running = ready(70).start(now: t0);
      final paused = running.stop(now: t0);
      expect(paused.phase, RestTimerPhase.paused);
      expect(paused.pausedRemainingSeconds, 70);

      final resumeAt = t0.add(const Duration(seconds: 30));
      final resumed = paused.start(now: resumeAt);
      expect(resumed.phase, RestTimerPhase.running);
      expect(resumed.remainingSecondsAt(resumeAt), 70);
      expect(resumed.pausedRemainingSeconds, isNull);
    });

    test('Restzeit beim Stop wird auf volle Sekunden aufgerundet', () {
      final running = ready(70).start(now: t0);
      final paused = running.stop(
        now: t0.add(const Duration(milliseconds: 1500)),
      );
      expect(paused.pausedRemainingSeconds, 69);
    });

    test('Stop nach Ablauf der Zeit wird zu expired', () {
      final state = ready(60).start(now: t0);
      final stopped = state.stop(now: t0.add(const Duration(seconds: 61)));
      expect(stopped.phase, RestTimerPhase.expired);
    });

    test('Stop aus Bereit ist ungültig', () {
      expect(() => ready().stop(now: t0), throwsA(isA<RestTimerException>()));
    });
  });

  group('Schließen setzt zurück', () {
    test('X bei 3:00 mit 1:00 Rest öffnet wieder 3:00 bereit', () {
      final running = ready().start(now: t0);
      final later = t0.add(const Duration(seconds: 120));
      expect(running.remainingSecondsAt(later), 60);

      final closed = running.close();
      expect(closed.phase, RestTimerPhase.ready);
      expect(closed.baseDurationSeconds, 180);
      expect(closed.remainingSecondsAt(later), 180);
      expect(closed.targetAtUtc, isNull);
    });

    test('X aus Pause verwirft die Restzeit', () {
      final closed = ready().start(now: t0).stop(now: t0).close();
      expect(closed.phase, RestTimerPhase.ready);
      expect(closed.pausedRemainingSeconds, isNull);
      expect(closed.remainingSecondsAt(t0), 180);
    });
  });

  group('Ablauf signalisieren', () {
    test('Ablauf zeigt 0 und startet nichts automatisch', () {
      final running = ready(60).start(now: t0);
      final expired = running.expire(now: t0.add(const Duration(seconds: 60)));
      expect(expired.phase, RestTimerPhase.expired);
      expect(
        expired.remainingSecondsAt(t0.add(const Duration(seconds: 90))),
        0,
      );
      expect(expired.isExpiredAt(t0.add(const Duration(seconds: 90))), isTrue);
    });

    test('Laufender Timer nach Zielzeit liefert nie negative Restzeit', () {
      final running = ready(60).start(now: t0);
      expect(
        running.remainingSecondsAt(t0.add(const Duration(seconds: 90))),
        0,
      );
    });

    test('expire vor Zielzeit ist ohne Wirkung', () {
      final running = ready(60).start(now: t0);
      expect(
        running.expire(now: t0.add(const Duration(seconds: 59))),
        same(running),
      );
    });

    test(
      'nach Ablauf startet eine neue Pause nur manuell mit der Ausgangsdauer',
      () {
        final expiredAt = t0.add(const Duration(seconds: 60));
        final expired = ready(60).start(now: t0).expire(now: expiredAt);
        final restarted = expired.start(now: expiredAt);
        expect(restarted.phase, RestTimerPhase.running);
        expect(restarted.remainingSecondsAt(expiredAt), 60);
        expect(restarted.generation, greaterThan(expired.generation));
      },
    );

    test('Rückkehr zur Trainingszeit erst nach acknowledgeNextSetRecorded', () {
      final expired = ready(60)
          .start(now: t0)
          .expire(now: t0.add(const Duration(seconds: 60)));
      expect(expired.phase, RestTimerPhase.expired);
      expect(
        () => expired.adjust(15, now: t0),
        throwsA(isA<RestTimerException>()),
      );

      final ready2 = expired.acknowledgeNextSetRecorded();
      expect(ready2.phase, RestTimerPhase.ready);
      expect(ready2.baseDurationSeconds, 60);
      expect(ready2.generation, greaterThan(expired.generation));
    });
  });

  group('Generation und Zustandsänderungen', () {
    test('jede Zustandsänderung erhöht die Generation', () {
      final start = ready();
      final running = start.start(now: t0);
      final paused = running.stop(now: t0);
      final resumed = paused.start(now: t0);
      expect(running.generation, start.generation + 1);
      expect(paused.generation, running.generation + 1);
      expect(resumed.generation, paused.generation + 1);
    });

    test('ungültige Eingaben werden abgewiesen', () {
      expect(
        () =>
            RestTimerState.ready(workoutId: workoutId, baseDurationSeconds: 4),
        throwsArgumentError,
      );
      expect(() => ready().selectShortcut(1801, now: t0), throwsArgumentError);
    });

    test('JSON-Roundtrip erhält jede Phase', () {
      final running = ready().start(now: t0);
      final states = [
        ready(90),
        running,
        running.stop(now: t0),
        running.expire(now: t0.add(const Duration(seconds: 200))),
      ];
      for (final state in states) {
        final decoded = RestTimerState.fromJson(state.toJson());
        expect(decoded.phase, state.phase);
        expect(decoded.generation, state.generation);
        expect(decoded.baseDurationSeconds, state.baseDurationSeconds);
        expect(decoded.targetAtUtc, state.targetAtUtc);
        expect(decoded.pausedRemainingSeconds, state.pausedRemainingSeconds);
      }
    });
  });

  group('RestTimerShortcuts', () {
    test('Standard ist 1:00, 2:00 und 3:00', () {
      expect(RestTimerShortcuts.defaults.seconds, [60, 120, 180]);
    });

    test('hinzufügen hängt an, ohne Duplikate', () {
      final shortcuts = RestTimerShortcuts.defaults.add(150).add(150).add(60);
      expect(shortcuts.seconds, [60, 120, 180, 150]);
    });

    test('verschieben ändert die Reihenfolge', () {
      final defaults = RestTimerShortcuts.defaults;
      expect(defaults.move(2, 0).seconds, [180, 60, 120]);
      expect(defaults.move(0, 2).seconds, [120, 180, 60]);
      expect(defaults.move(1, 1), defaults);
      expect(() => defaults.move(3, 0), throwsRangeError);
      expect(() => defaults.move(0, 3), throwsRangeError);
    });

    test('Reihenfolge der Eingabe bleibt erhalten', () {
      expect(RestTimerShortcuts.fromSeconds([180, 60, 180]).seconds, [180, 60]);
    });

    test('löschen entfernt den Wert', () {
      expect(RestTimerShortcuts.defaults.remove(120).seconds, [60, 180]);
    });

    test('Grenzen 5 s bis 30 min werden durchgesetzt', () {
      expect(() => RestTimerShortcuts.defaults.add(4), throwsArgumentError);
      expect(() => RestTimerShortcuts.defaults.add(1801), throwsArgumentError);
      expect(RestTimerShortcuts.defaults.add(5).seconds, contains(5));
      expect(RestTimerShortcuts.defaults.add(1800).seconds, contains(1800));
    });
  });
}
