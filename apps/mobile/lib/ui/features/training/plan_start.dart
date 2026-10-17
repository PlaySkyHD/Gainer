import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../core/components/components.dart';
import 'active_workout_controller.dart';
import 'training_plans_view_model.dart';
import 'workout_screen.dart';

/// Startet ein Training aus einem Plan und öffnet es. Existiert schon ein
/// aktives Training, wird dessen Fortsetzen angeboten statt ein zweites anzulegen.
Future<void> startPlanWorkout(
  BuildContext context, {
  required TrainingLogRepository repository,
  required ActiveWorkoutController activeWorkout,
  required String planId,
}) async {
  final running = await repository.readActiveWorkout();
  if (!context.mounted) return;

  String workoutId;
  if (running != null) {
    final resume = await showGainerStackedDialog<bool>(
      context: context,
      title: 'Aktives Training',
      message:
          'Es kann nur ein aktives Training geben. „${running.title}“ läuft noch.',
      actions: const [
        GainerDialogAction(label: 'Aktives Training fortsetzen', value: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (resume != true || !context.mounted) return;
    workoutId = running.workoutId;
  } else {
    try {
      workoutId = (await repository.startFromPlan(planId)).workoutId;
    } on ActiveWorkoutExistsException catch (error) {
      workoutId = error.workoutId;
    } catch (error) {
      if (context.mounted) {
        await showGainerStackedDialog<bool>(
          context: context,
          title: 'Training nicht gestartet',
          message: planErrorMessage(
            error,
            'Das Training konnte nicht gestartet werden. Es wurde nichts gespeichert.',
          ),
          actions: const [GainerDialogAction(label: 'OK', value: true)],
        );
      }
      return;
    }
  }

  await activeWorkout.load();
  if (!context.mounted) return;
  await openWorkoutScreen(
    context,
    repository: repository,
    activeWorkout: activeWorkout,
    workoutId: workoutId,
  );
}
