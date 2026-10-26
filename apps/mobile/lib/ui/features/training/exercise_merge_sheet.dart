import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../core/components/components.dart';
import 'exercise_catalog_format.dart';
import 'exercise_picker_sheet.dart';

/// Wählt die Zielübung aus und führt die eigene Übung [source] zusammen.
/// Liefert true, wenn die Zusammenführung ausgeführt wurde.
Future<bool> showExerciseMergeSheet(
  BuildContext context, {
  required TrainingLogRepository repository,
  required CatalogExercise source,
}) async {
  final picked = await showExercisePicker(
    context,
    repository: repository,
    allowSuperset: false,
    title: 'Zielübung wählen',
    excludedExerciseId: source.id,
  );
  if (picked == null || picked.exercises.isEmpty || !context.mounted) {
    return false;
  }
  return mergeExerciseInto(
    context,
    repository: repository,
    source: source,
    target: picked.exercises.first,
  );
}

/// Bestätigt die Zusammenführung und ruft das Repository auf.
Future<bool> mergeExerciseInto(
  BuildContext context, {
  required TrainingLogRepository repository,
  required CatalogExercise source,
  required CatalogExercise target,
}) async {
  if (target.id == source.id) {
    await _showMessage(context, 'Quelle und Ziel müssen verschieden sein.');
    return false;
  }
  final confirmed = await showGainerStackedDialog<bool>(
    context: context,
    title: 'Übungen zusammenführen?',
    message:
        '„${source.name}“ wird in „${target.name}“ zusammengeführt. Trainings und Pläne zählen danach zu „${target.name}“, „${source.name}“ wird archiviert.',
    actions: const [
      GainerDialogAction(label: 'Zusammenführen', value: true),
      GainerDialogAction(label: 'Abbrechen', value: false),
    ],
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await repository.mergeExercises(
      sourceExerciseId: source.id,
      targetExerciseId: target.id,
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      await _showMessage(
        context,
        catalogErrorMessage(
          error,
          'Die Übungen konnten nicht zusammengeführt werden.',
        ),
      );
    }
    return false;
  }
}

Future<void> _showMessage(BuildContext context, String message) {
  return showGainerStackedDialog<bool>(
    context: context,
    title: 'Hinweis',
    message: message,
    actions: const [GainerDialogAction(label: 'OK', value: true)],
  ).then((_) {});
}
