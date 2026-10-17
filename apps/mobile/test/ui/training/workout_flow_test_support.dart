import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_plans_test_support.dart';
import 'training_test_support.dart';

/// Aktives Training am 17. Oktober um 8 Uhr mit den gegebenen Blöcken. Die
/// Uhr steht danach auf 9 Uhr, damit ein Beenden eine gültige Endzeit setzt.
Future<String> startActiveWorkout(
  WidgetTester tester,
  TrainingHarness harness,
  ActiveWorkoutController active, {
  List<WorkoutBlock> blocks = const [],
}) async {
  final workout = await tester.runAsync(
    () => harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: blocks,
    ),
  );
  await tester.runAsync(active.load);
  harness.now = DateTime.utc(2026, 10, 17, 9);
  return workout!.workoutId;
}

/// Öffnet das Training aus einem Host-Bildschirm, damit das Schließen den
/// Host sichtbar lässt.
Future<void> pumpWorkoutFromHost(
  WidgetTester tester,
  TrainingHarness harness,
  ActiveWorkoutController active,
  String workoutId,
) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    trainingTestApp(
      home: Builder(
        builder: (context) => Center(
          child: CupertinoButton(
            onPressed: () => openWorkoutScreen(
              context,
              repository: harness.repository,
              activeWorkout: active,
              workoutId: workoutId,
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Öffnen'));
  await settle(tester);
}

/// Finder über das Semantics-Widget mit diesem Label.
Finder labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Future<void> searchPicker(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(CupertinoSearchTextField), query);
  await settle(tester);
}

Future<Workout?> storedWorkout(
  WidgetTester tester,
  TrainingHarness harness,
  String workoutId,
) async {
  return tester.runAsync<Workout?>(
    () => harness.repository.readWorkout(workoutId),
  );
}
