import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';

import 'training_test_support.dart';

Finder _inDialog(String label) => find.descendant(
  of: find.byType(GainerStackedDialog<bool>),
  matching: find.text(label),
);

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      trainingTestApp(
        home: TrainingHomeScreen(
          repository: harness.repository,
          activeWorkout: activeWorkout,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('Monatsgruppen und Trainingszeile', (tester) async {
    await tester.runAsync(() async {
      await harness.seedWorkout(
        title: 'Push',
        start: DateTime(2026, 10, 2, 7).toUtc(),
        end: DateTime(2026, 10, 2, 8).toUtc(),
      );
      await harness.seedWorkout(
        title: 'Ganzkörper',
        start: DateTime(2026, 9, 28, 17).toUtc(),
        end: DateTime(2026, 9, 28, 18).toUtc(),
      );
      await harness.seedWorkout(
        title: 'Legs 2',
        start: DateTime(2026, 10, 15, 18).toUtc(),
        end: DateTime(2026, 10, 15, 20, 9).toUtc(),
        blocks: [
          strengthBlock('Beinbeuger', 2, id: 'a'),
          strengthBlock('Beinstrecker', 3, id: 'b'),
        ],
      );
    });
    await pumpHome(tester);

    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(find.text('2 Trainings'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('1 Training'), findsOneWidget);
    expect(find.text('Do'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('Legs 2'), findsOneWidget);
    expect(find.text('129 min'), findsOneWidget);
    expect(find.text('2x Beinbeuger'), findsOneWidget);
    expect(find.text('3x Beinstrecker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wischen zum Löschen erst nach Bestätigung', (tester) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Legs 2',
        start: DateTime(2026, 10, 15, 18).toUtc(),
        end: DateTime(2026, 10, 15, 19).toUtc(),
      ),
    );
    await pumpHome(tester);

    await tester.drag(find.text('Legs 2'), const Offset(-500, 0));
    await settle(tester);
    expect(_inDialog('Löschen'), findsOneWidget);
    expect(find.text('Legs 2'), findsOneWidget);

    await tester.tap(_inDialog('Abbrechen'));
    await settle(tester);
    expect(find.text('Legs 2'), findsOneWidget);

    await tester.drag(find.text('Legs 2'), const Offset(-500, 0));
    await settle(tester);
    await tester.tap(_inDialog('Löschen'));
    await settle(tester);
    expect(find.text('Legs 2'), findsNothing);
    final remaining = await tester.runAsync(harness.repository.readDiary);
    expect(remaining, isEmpty);
  });

  testWidgets('Bearbeiten-Modus löscht per rotem Minus nach Bestätigung', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push',
        start: DateTime(2026, 10, 14, 18).toUtc(),
        end: DateTime(2026, 10, 14, 19).toUtc(),
      ),
    );
    await pumpHome(tester);

    await tester.tap(find.text('Bearbeiten'));
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.minus_circle_fill));
    await settle(tester);
    await tester.tap(_inDialog('Löschen'));
    await settle(tester);

    expect(find.text('Push'), findsNothing);
    expect(find.text('Noch keine Trainings'), findsOneWidget);
  });

  testWidgets('+ startet ein leeres Training', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byIcon(CupertinoIcons.add));
    await settle(tester);

    expect(find.text('Beenden'), findsOneWidget);
    final active = await tester.runAsync(harness.repository.readActiveWorkout);
    expect(active?.title, 'Training');
  });

  testWidgets(
    '+ bei aktivem Training bietet Fortsetzen statt zweitem Training',
    (tester) async {
      await tester.runAsync(() async {
        await harness.seedWorkout(
          title: 'Push',
          start: DateTime(2026, 10, 17, 8).toUtc(),
        );
        await activeWorkout.load();
      });
      await pumpHome(tester);

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await settle(tester);
      expect(find.text('Aktives Training fortsetzen'), findsOneWidget);
      await tester.tap(_inDialog('Aktives Training fortsetzen'));
      await settle(tester);

      expect(find.text('Beenden'), findsOneWidget);
      final diary = await tester.runAsync(harness.repository.readDiary);
      expect(diary, hasLength(1));
    },
  );

  testWidgets('leerer Zustand bietet Training starten', (tester) async {
    await pumpHome(tester);

    expect(find.text('Noch keine Trainings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('training-start-empty')));
    await settle(tester);

    expect(find.text('Beenden'), findsOneWidget);
  });

  testWidgets('Pläne und Statistik zeigen eigene Segmente', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Pläne'));
    await settle(tester);
    expect(find.text('Noch keine Trainings'), findsNothing);
    expect(find.byIcon(CupertinoIcons.add), findsNothing);

    await tester.tap(find.text('Statistik'));
    await settle(tester);
    expect(find.text('Noch keine Statistik'), findsOneWidget);
  });
}
