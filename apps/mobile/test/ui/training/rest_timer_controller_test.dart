import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/services/platform/platform_ports.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';

import 'rest_timer_test_support.dart';

void main() {
  group('Pausentimer nur manuell starten', () {
    testWidgets('Satz erfasst ohne Timeraktion startet keinen Timer', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.onSetRecorded();
        await advanceRestTimer(tester, fixture.clock, 60);

        expect(controller.phase, RestTimerPhase.ready);
        expect(fixture.notifications.scheduled, isEmpty);
      });
    });

    testWidgets('Timeransicht öffnen zeigt 3:00 bereit ohne Lauf', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        expect(controller.phase, RestTimerPhase.ready);
        expect(controller.remainingSeconds, 180);
        await advanceRestTimer(tester, fixture.clock, 5);
        expect(controller.phase, RestTimerPhase.ready);
        expect(controller.remainingSeconds, 180);
      });
    });
  });

  group('Dauer wählen und Shortcuts', () {
    testWidgets('Shortcut 2:30 startet einen Timer mit 2:30', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.addShortcut(150);
        await controller.selectShortcut(150);

        await controller.start();

        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 150);
        expect(
          fixture.notifications.scheduled.single.targetAtUtc,
          restTimerStart.add(const Duration(seconds: 150)),
        );
      });
    });

    testWidgets('+15 s bei 0:40 ergibt 0:55 und plant neu', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 140);
        expect(controller.remainingSeconds, 40);

        await controller.adjust(15);

        expect(controller.remainingSeconds, 55);
        expect(fixture.notifications.scheduled, hasLength(2));
        expect(
          fixture.notifications.scheduled.last.targetAtUtc,
          fixture.clock.now.add(const Duration(seconds: 55)),
        );
        expect(
          fixture.notifications.scheduled.last.generation,
          greaterThan(fixture.notifications.scheduled.first.generation),
        );
      });
    });

    testWidgets('Shortcuts lassen sich anlegen, löschen und bleiben erhalten', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.addShortcut(150);
        expect(controller.shortcuts.seconds, [60, 120, 150, 180]);
        await controller.removeShortcut(60);
        expect(controller.shortcuts.seconds, [120, 150, 180]);

        final reloaded = fixture.controllerFor();
        await reloaded.load();
        expect(reloaded.shortcuts.seconds, [120, 150, 180]);
      });
    });

    testWidgets('Shortcut wird während des Laufs nicht gewechselt', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();

        await controller.selectShortcut(60);

        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 180);
      });
    });
  });

  group('Stop pausiert, Start setzt fort', () {
    testWidgets('Stop bei 1:10 und Start nach 30 s läuft mit 1:10 weiter', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.selectShortcut(70);
        await controller.start();
        expect(controller.remainingSeconds, 70);

        final cancelsBeforeStop = fixture.notifications.cancelCount;
        await controller.stop();
        expect(controller.phase, RestTimerPhase.paused);
        expect(fixture.notifications.cancelCount, cancelsBeforeStop + 1);
        await advanceRestTimer(tester, fixture.clock, 30);
        expect(controller.remainingSeconds, 70);

        await controller.start();

        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 70);
        expect(
          fixture.notifications.scheduled.last.targetAtUtc,
          fixture.clock.now.add(const Duration(seconds: 70)),
        );
      });
    });
  });

  group('Schließen setzt zurück', () {
    testWidgets(
      'X nach laufendem Timer zeigt 3:00 bereit und entfernt die Benachrichtigung',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await controller.start();
          await advanceRestTimer(tester, fixture.clock, 120);
          final cancelsBefore = fixture.notifications.cancelCount;

          await controller.close();

          expect(controller.phase, RestTimerPhase.ready);
          expect(controller.remainingSeconds, 180);
          expect(fixture.notifications.cancelCount, cancelsBefore + 1);

          await advanceRestTimer(tester, fixture.clock, 600);
          final reopened = fixture.controllerFor();
          await reopened.load();
          expect(reopened.phase, RestTimerPhase.ready);
          expect(reopened.remainingSeconds, 180);
        });
      },
    );
  });

  group('Ablauf signalisieren', () {
    testWidgets('Ablauf im Vordergrund spielt Ton und Haptik genau einmal', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();

        await advanceRestTimer(tester, fixture.clock, 180);

        expect(controller.phase, RestTimerPhase.expired);
        expect(controller.remainingSeconds, 0);
        expect(fixture.alerts.plays, 1);
        expect(fixture.haptics.intents, [HapticIntent.timerComplete]);

        await advanceRestTimer(tester, fixture.clock, 30);
        expect(controller.phase, RestTimerPhase.expired);
        expect(controller.remainingSeconds, 0);
        expect(fixture.alerts.plays, 1);
        expect(fixture.haptics.intents, hasLength(1));
      });
    });

    testWidgets('Abgelaufener Timer startet nicht ohne Nutzeraktion neu', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 200);

        expect(controller.phase, RestTimerPhase.expired);
        expect(fixture.notifications.scheduled, hasLength(1));
      });
    });

    testWidgets(
      'Rückkehr zur Trainingszeit erst nach vollständigem Satz (onSetRecorded)',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await controller.selectShortcut(60);
          await controller.start();
          await advanceRestTimer(tester, fixture.clock, 60);
          expect(controller.phase, RestTimerPhase.expired);

          // Gewicht eingetragen, Wiederholungen noch offen: kein Satz erfasst.
          await advanceRestTimer(tester, fixture.clock, 20);
          expect(controller.phase, RestTimerPhase.expired);
          expect(controller.remainingSeconds, 0);

          await controller.onSetRecorded();
          expect(controller.phase, RestTimerPhase.ready);
          expect(controller.remainingSeconds, 60);
        });
      },
    );

    testWidgets(
      'Verweigerte Benachrichtigungen blockieren das Training nicht',
      (tester) {
        return runRestTimerTest((fixture) async {
          fixture.notifications.permission = false;
          final controller = fixture.controllerFor();
          await controller.load();

          await controller.start();
          await advanceRestTimer(tester, fixture.clock, 30);

          expect(controller.phase, RestTimerPhase.running);
          expect(controller.remainingSeconds, 150);
          expect(controller.notificationsUnavailable, isTrue);
          expect(fixture.notifications.scheduled, isEmpty);
        });
      },
    );

    testWidgets(
      'Ablauf im Hintergrund erzeugt keinen Ton, Anzeige bleibt 0:00',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await controller.selectShortcut(60);
          await controller.start();

          controller.didChangeAppLifecycleState(AppLifecycleState.paused);
          await advanceRestTimer(tester, fixture.clock, 120);
          controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();

          expect(controller.phase, RestTimerPhase.expired);
          expect(controller.remainingSeconds, 0);
          expect(fixture.alerts.plays, 0);
          expect(fixture.haptics.intents, isEmpty);
        });
      },
    );
  });

  group('Eine Timerwahrheit', () {
    testWidgets('Rückkehr aus dem Hintergrund nach 30 s zeigt 2:30', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();

        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        await advanceRestTimer(tester, fixture.clock, 30);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();

        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 150);
        expect(fixture.notifications.scheduled, hasLength(1));
      });
    });

    testWidgets(
      'Prozessende während der Pause stellt den Timer ohne doppelte Benachrichtigung her',
      (tester) {
        return runRestTimerTest((fixture) async {
          final first = fixture.controllerFor();
          await first.load();
          await first.start();
          await advanceRestTimer(tester, fixture.clock, 30);

          // Neustart: der neue Controller liest nur den Speicher und plant nicht erneut.
          final restarted = fixture.controllerFor();
          await restarted.load();

          expect(restarted.phase, RestTimerPhase.running);
          expect(restarted.remainingSeconds, 150);
          expect(fixture.notifications.scheduled, hasLength(1));
        });
      },
    );

    testWidgets('Prozessende nach Ablauf stellt den Timer als abgelaufen her', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final first = fixture.controllerFor();
        await first.load();
        await first.start();
        await advanceRestTimer(tester, fixture.clock, 200);
        expect(fixture.alerts.plays, 1);

        final restarted = fixture.controllerFor();
        await restarted.load();

        expect(restarted.phase, RestTimerPhase.expired);
        expect(restarted.remainingSeconds, 0);
        // Der Ton gehört zum Ablauf im Vordergrund und wird nach dem Neustart nicht wiederholt.
        expect(fixture.alerts.plays, 1);
      });
    });
  });

  group('Trainingsende', () {
    testWidgets(
      'endForWorkout räumt Zustand und Benachrichtigung ab und nimmt danach keine Aktionen an',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await controller.start();
          final cancelsBefore = fixture.notifications.cancelCount;

          await controller.endForWorkout();
          await controller.start();

          expect(controller.phase, RestTimerPhase.ready);
          expect(fixture.notifications.cancelCount, cancelsBefore + 1);
          expect(fixture.notifications.scheduled, hasLength(1));
          expect(
            fixture.store.timerFor(restTimerWorkoutId)!.phase,
            RestTimerPhase.ready,
          );
        });
      },
    );
  });
}
