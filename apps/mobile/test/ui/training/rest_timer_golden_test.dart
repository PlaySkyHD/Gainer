import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_bar.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_sheet.dart';

import 'rest_timer_test_support.dart';
import 'training_test_support.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness.name;

    testWidgets('Pausenleiste bereit $name', (tester) {
      return runRestTimerTest((fixture) async {
        _phoneSize(tester);
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpBar(tester, controller, brightness);

        await expectLater(
          find.byType(RestTimerBar),
          matchesGoldenFile('goldens/rest_timer_bar_ready_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('Pausenleiste laufend $name', (tester) {
      return runRestTimerTest((fixture) async {
        _phoneSize(tester);
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 30);
        await _pumpBar(tester, controller, brightness);

        await expectLater(
          find.byType(RestTimerBar),
          matchesGoldenFile('goldens/rest_timer_bar_running_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('Pausenleiste abgelaufen $name', (tester) {
      return runRestTimerTest((fixture) async {
        _phoneSize(tester);
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 200);
        await _pumpBar(tester, controller, brightness);

        await expectLater(
          find.byType(RestTimerBar),
          matchesGoldenFile('goldens/rest_timer_bar_expired_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('Timeransicht bereit $name', (tester) {
      return runRestTimerTest((fixture) async {
        _phoneSize(tester);
        final controller = fixture.controllerFor();
        await controller.load();
        await _pumpSheet(tester, controller, brightness);

        await expectLater(
          find.byType(RestTimerSheet),
          matchesGoldenFile('goldens/rest_timer_sheet_ready_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('Timeransicht laufend $name', (tester) {
      return runRestTimerTest((fixture) async {
        _phoneSize(tester);
        final controller = fixture.controllerFor();
        await controller.load();
        await controller.start();
        await advanceRestTimer(tester, fixture.clock, 30);
        await _pumpSheet(tester, controller, brightness);

        await expectLater(
          find.byType(RestTimerSheet),
          matchesGoldenFile('goldens/rest_timer_sheet_running_$name.png'),
        );
      });
    }, tags: ['golden']);
  }
}

Future<void> _pumpBar(
  WidgetTester tester,
  RestTimerController controller,
  Brightness brightness,
) async {
  await tester.pumpWidget(
    trainingTestApp(
      brightness: brightness,
      home: CupertinoPageScaffold(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RestTimerBar(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpSheet(
  WidgetTester tester,
  RestTimerController controller,
  Brightness brightness,
) async {
  await tester.pumpWidget(
    trainingTestApp(
      brightness: brightness,
      home: CupertinoPageScaffold(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RestTimerSheet(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
