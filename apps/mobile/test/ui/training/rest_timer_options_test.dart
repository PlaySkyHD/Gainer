import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_option_sheets.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_sheet.dart';

import 'rest_timer_test_support.dart';
import 'training_test_support.dart';

Future<void> _pumpSheet(
  WidgetTester tester,
  RestTimerController controller,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    trainingTestApp(
      home: Align(
        alignment: Alignment.bottomCenter,
        child: RestTimerSheet(controller: controller),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Timer-Optionen'));
  await tester.pumpAndSettle();
}

void main() {
  group('Controller', () {
    testWidgets('Shortcut startet den Timer sofort mit dieser Dauer', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.startShortcut(120);

        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 120);
        expect(fixture.notifications.scheduled, hasLength(1));
        expect(
          fixture.notifications.scheduled.single.targetAtUtc,
          restTimerStart.add(const Duration(seconds: 120)),
        );
      });
    });

    testWidgets('Shortcut startet auch nach Ablauf, nicht während Lauf/Pause', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.startShortcut(60);
        await controller.startShortcut(120);
        expect(controller.remainingSeconds, 60);

        await controller.stop();
        await controller.startShortcut(120);
        expect(controller.phase, RestTimerPhase.paused);

        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 60);
        expect(controller.phase, RestTimerPhase.expired);
        await controller.startShortcut(90);
        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 90);
      });
    });

    testWidgets('Verschieben ändert die Reihenfolge dauerhaft', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.moveShortcut(2, 0);
        await controller.moveShortcut(1, 1);

        expect(controller.shortcuts.seconds, [180, 60, 120]);
        expect(fixture.store.shortcutsForTest.seconds, [180, 60, 120]);
      });
    });

    testWidgets('Tonwahl spielt den Ton, speichert ihn und gilt beim Planen', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        expect(controller.soundId, 'digital_alarm');

        await controller.selectSound('gong');
        await controller.startShortcut(60);

        expect(fixture.alerts.played, ['gong']);
        expect(controller.soundId, 'gong');
        expect(fixture.notifications.scheduled.single.soundId, 'gong');
        await fixture.preferences.read();
        expect(fixture.preferences.timerSoundId.value, 'gong');
      });
    });

    testWidgets('Tonwechsel bei laufendem Timer plant neu mit neuem Ton', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.startShortcut(60);

        await controller.selectSound('chime');

        expect(fixture.notifications.scheduled, hasLength(2));
        expect(fixture.notifications.scheduled.last.soundId, 'chime');
        expect(
          fixture.notifications.scheduled.last.generation,
          fixture.notifications.scheduled.first.generation,
        );
      });
    });

    testWidgets('gleicher Ton wird abgespielt, aber nicht neu gespeichert', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.selectSound('digital_alarm');
        await controller.selectSound('unbekannt');

        expect(fixture.alerts.played, ['digital_alarm', 'digital_alarm']);
        expect(controller.soundId, 'digital_alarm');
      });
    });

    testWidgets('Ablauf ohne Benachrichtigung spielt den gewählten Ton', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        fixture.notifications.permission = false;
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.selectSound('radar');
        fixture.alerts.played.clear();
        await controller.startShortcut(60);

        await advanceRestTimer(tester, fixture.clock, 60);

        expect(fixture.alerts.played, ['radar']);
      });
    });

    testWidgets('Auto-Start lässt sich ein- und ausschalten', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        expect(controller.autoStartEnabled, isFalse);

        await controller.setAutoStart(true);
        expect(controller.autoStartEnabled, isTrue);
        await controller.setAutoStart(true);
        await controller.setAutoStart(false);
        expect(controller.autoStartEnabled, isFalse);
      });
    });

    testWidgets('autoStart startet nur im Zustand bereit oder abgelaufen', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();

        await controller.autoStart();
        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 180);

        await advanceRestTimer(tester, fixture.clock, 40);
        await controller.autoStart();
        expect(controller.remainingSeconds, 140);

        await controller.stop();
        await controller.autoStart();
        expect(controller.phase, RestTimerPhase.paused);

        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 140);
        expect(controller.phase, RestTimerPhase.expired);
        await controller.autoStart();
        expect(controller.phase, RestTimerPhase.running);
        expect(controller.remainingSeconds, 180);
      });
    });
  });

  group('Timeransicht', () {
    testWidgets(
      'Shortcut-Chips: „+“ vorne, Tippen startet, dann ausgeblendet',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await _pumpSheet(tester, controller);

          final plus = tester.getCenter(
            find.bySemanticsLabel('Shortcut hinzufügen'),
          );
          final first = tester.getCenter(find.text('01:00'));
          expect(plus.dx, lessThan(first.dx));
          expect(find.text('02:00'), findsOneWidget);
          expect(find.text('03:00'), findsNWidgets(2));

          await tester.tap(find.text('02:00'));
          await tester.pump();

          expect(controller.phase, RestTimerPhase.running);
          expect(controller.remainingSeconds, 120);
          expect(find.bySemanticsLabel('Shortcut hinzufügen'), findsNothing);
          expect(find.text('01:00'), findsNothing);

          await controller.stop();
          await tester.pump();
          expect(find.text('01:00'), findsNothing);

          await controller.close();
          await tester.pump();
          expect(find.text('01:00'), findsOneWidget);
        });
      },
    );

    testWidgets('Menü zeigt drei Einträge und den Zustand der Checkbox', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpSheet(tester, controller);

        await _openMenu(tester);

        expect(find.text('Timersound'), findsOneWidget);
        expect(find.text('Timer bearbeiten'), findsOneWidget);
        expect(find.text('Timer automatisch starten'), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.square), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.checkmark_square_fill), findsNothing);

        await tester.tap(find.text('Timer automatisch starten'));
        await tester.pumpAndSettle();
        expect(controller.autoStartEnabled, isTrue);
        expect(find.text('Timersound'), findsNothing);

        await _openMenu(tester);
        expect(
          find.byIcon(CupertinoIcons.checkmark_square_fill),
          findsOneWidget,
        );
        await tester.tap(find.text('Timer automatisch starten'));
        await tester.pumpAndSettle();
        expect(controller.autoStartEnabled, isFalse);
      });
    });

    testWidgets('Menü lässt sich durch Tippen daneben schließen', (tester) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpSheet(tester, controller);
        await _openMenu(tester);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text('Timersound'), findsNothing);
        expect(controller.autoStartEnabled, isFalse);
      });
    });

    testWidgets('Timersound: Antippen wählt, hakt ab und spielt den Ton', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpSheet(tester, controller);
        await _openMenu(tester);
        await tester.tap(find.text('Timersound'));
        await tester.pumpAndSettle();

        expect(find.text('Digitaler Wecker'), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.checkmark), findsNWidgets(2));

        await tester.tap(find.text('Gong'));
        await tester.pumpAndSettle();

        expect(fixture.alerts.played, ['gong']);
        expect(controller.soundId, 'gong');
        expect(find.byIcon(CupertinoIcons.checkmark), findsNWidgets(2));

        await tester.tap(find.byKey(restTimerOptionDoneKey));
        await tester.pumpAndSettle();
        expect(find.text('Gong'), findsNothing);
      });
    });

    testWidgets('Timer bearbeiten: löschen, sortieren und hinzufügen', (
      tester,
    ) {
      return runRestTimerTest((fixture) async {
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpSheet(tester, controller);
        await _openMenu(tester);
        await tester.tap(find.text('Timer bearbeiten'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(CupertinoIcons.minus_circle_fill).last);
        await tester.pumpAndSettle();
        expect(controller.shortcuts.seconds, [60, 120]);

        await tester.timedDrag(
          find.byIcon(CupertinoIcons.line_horizontal_3).first,
          const Offset(0, 60),
          const Duration(milliseconds: 600),
        );
        await tester.pumpAndSettle();
        expect(controller.shortcuts.seconds, [120, 60]);

        await tester.tap(find.byIcon(CupertinoIcons.plus).last);
        await tester.pumpAndSettle();
        expect(find.text('Abbrechen'), findsOneWidget);
        expect(find.text('Timer hinzufügen'), findsOneWidget);
        await tester.tap(find.text('Hinzufügen'));
        await tester.pumpAndSettle();

        expect(controller.shortcuts.seconds, [120, 60, 180]);

        await tester.tap(find.byKey(restTimerOptionDoneKey));
        await tester.pumpAndSettle();
        expect(find.text('Timer bearbeiten'), findsNothing);
        expect(find.text('02:00'), findsOneWidget);
      });
    });

    testWidgets(
      'Dauerwähler: Abbrechen legt nichts an, Auswahl wird übernommen',
      (tester) {
        return runRestTimerTest((fixture) async {
          final controller = fixture.controllerFor();
          await controller.load();
          await _pumpSheet(tester, controller);

          await tester.tap(find.bySemanticsLabel('Shortcut hinzufügen'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Abbrechen'));
          await tester.pumpAndSettle();
          expect(controller.shortcuts.seconds, [60, 120, 180]);

          await tester.tap(find.bySemanticsLabel('Shortcut hinzufügen'));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(CupertinoPicker).first,
            const Offset(0, -64),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Hinzufügen'));
          await tester.pumpAndSettle();

          expect(controller.shortcuts.seconds, [60, 120, 180, 240]);
        });
      },
    );
  });
}
