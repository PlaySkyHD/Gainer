import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';

enum _ExistingPlanChoice { overwrite, createNew, cancel }

/// Speichert ein Training als Plan. Gibt es schon einen nicht archivierten Plan
/// gleichen Namens, fragt der Dialog, ob er überschrieben oder ein neuer angelegt wird.
Future<void> saveWorkoutAsPlanFlow(
  BuildContext context, {
  required TrainingLogRepository repository,
  required Workout workout,
}) async {
  try {
    final preview = await repository.previewPlanFromWorkout(workout.workoutId);
    var overwriteExisting = false;
    final existing = preview.existingPlan;
    if (existing != null) {
      if (!context.mounted) return;
      final choice = await showGainerStackedDialog<_ExistingPlanChoice>(
        context: context,
        title: 'Plan „${existing.name}“ existiert bereits',
        message:
            'Soll er durch die Übungen aus „${workout.title}“ ersetzt oder daneben als neuer Plan gespeichert werden?',
        actions: const [
          GainerDialogAction(
            label: 'Überschreiben',
            value: _ExistingPlanChoice.overwrite,
          ),
          GainerDialogAction(
            label: 'Als neuen Plan speichern',
            value: _ExistingPlanChoice.createNew,
          ),
          GainerDialogAction(
            label: 'Abbrechen',
            value: _ExistingPlanChoice.cancel,
          ),
        ],
      );
      if (choice == null || choice == _ExistingPlanChoice.cancel) return;
      overwriteExisting = choice == _ExistingPlanChoice.overwrite;
    }
    await repository.saveWorkoutAsPlan(
      workout.workoutId,
      overwriteExisting: overwriteExisting,
    );
  } catch (_) {
    if (context.mounted) {
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Plan nicht gespeichert',
        message: 'Das Training konnte nicht als Plan gespeichert werden. Es wurde nichts geändert.',
        actions: const [GainerDialogAction(label: 'OK', value: true)],
      );
    }
    return;
  }

  if (!context.mounted) return;
  await showGainerStackedDialog<bool>(
    context: context,
    title: 'Plan gespeichert',
    message: '„${workout.title}“ steht jetzt in den Trainingsplänen.',
    actions: const [GainerDialogAction(label: 'OK', value: true)],
  );
}
