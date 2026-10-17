import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_bar.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_sheet.dart';

import 'rest_timer_test_support.dart';
import 'training_test_support.dart';

void main() {
  testWidgets('Leiste zeigt im Bereit-Zustand 03:00', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerBar(controller: controller),
          ),
        ),
      );

      expect(find.text('03:00'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
    });
  });

  testWidgets('laufender Timer zeigt Stopp-Symbol und Restzeit', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await controller.start();
      await advanceRestTimer(tester, fixture.clock, 30);
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerBar(controller: controller),
          ),
        ),
      );

      expect(find.text('02:30'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.stop_fill), findsOneWidget);
    });
  });

  testWidgets('Trainingszeit steht links, solange kein Timer läuft', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerBar(
              controller: controller,
              trainingStartedAtUtc: restTimerStart.subtract(
                const Duration(minutes: 12, seconds: 5),
              ),
            ),
          ),
        ),
      );

      expect(find.text('12:05'), findsOneWidget);
    });
  });

  testWidgets('Antippen der Leiste öffnet die große Ansicht', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerBar(controller: controller),
          ),
        ),
      );

      await tester.tap(find.text('03:00'));
      await tester.pumpAndSettle();

      expect(find.text('+15s'), findsOneWidget);
      expect(find.text('Timer'), findsOneWidget);
    });
  });

  testWidgets('große Ansicht: +15s verlängert, Shortcut wählt Dauer', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerSheet(controller: controller),
          ),
        ),
      );

      await tester.tap(find.text('+15s'));
      await tester.pump();
      expect(controller.remainingSeconds, 195);

      await tester.tap(find.text('02:00'));
      await tester.pump();
      expect(controller.remainingSeconds, 120);
      expect(controller.phase, RestTimerPhase.ready);
    });
  });

  testWidgets('Shortcut löschen im Bearbeitungsmodus', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await tester.pumpWidget(
        trainingTestApp(
          home: Align(
            alignment: Alignment.bottomCenter,
            child: RestTimerSheet(controller: controller),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Shortcuts bearbeiten'));
      await tester.pump();
      await tester.tap(find.text('01:00'));
      await tester.pump();

      expect(controller.shortcuts.seconds, [120, 180]);
      expect(find.text('01:00'), findsNothing);
    });
  });

  testWidgets('X in der großen Ansicht beendet den Timer', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await controller.start();
      await tester.pumpWidget(
        trainingTestApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => showRestTimerSheet(context, controller),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Timer schließen'));
      await tester.pumpAndSettle();

      expect(controller.phase, RestTimerPhase.ready);
      expect(find.text('+15s'), findsNothing);
    });
  });

  testWidgets('Wischen nach unten minimiert, der Timer läuft weiter', (tester) {
    return runRestTimerTest((fixture) async {
      final controller = fixture.controllerFor();
      await controller.load();
      await controller.start();
      await tester.pumpWidget(
        trainingTestApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => showRestTimerSheet(context, controller),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      // Ein kurzer, langsamer Zug federt zurück.
      await tester.timedDrag(
        find.text('+15s'),
        const Offset(0, 30),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(find.text('+15s'), findsOneWidget);

      await tester.fling(find.text('+15s'), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();

      expect(find.text('+15s'), findsNothing);
      expect(controller.phase, RestTimerPhase.running);
    });
  });
}
