import 'package:flutter/cupertino.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../core/components/components.dart';
import 'active_workout_controller.dart';
import 'training_plans_view_model.dart';
import 'workout_screen.dart';

/// Laufendes Prüfen und Anlegen. Ein zweiter Tipp wartet darauf, statt erneut
/// zu prüfen und „Aktives Training“ über oder unter das gerade geöffnete
/// Training zu legen.
Future<String?>? _pendingStart;

/// Startet ein Training aus einem Plan und öffnet es. Existiert schon ein
/// aktives Training, wird dessen Fortsetzen angeboten statt ein zweites anzulegen.
Future<void> startPlanWorkout(
  BuildContext context, {
  required TrainingLogRepository repository,
  required ActiveWorkoutController activeWorkout,
  required String planId,
}) async {
  // Trainingsscreen und Dialoge liegen im Root-Navigator. Über ihn öffnet sich
  // das Training auch dann, wenn der auslösende Bereich während des Starts neu
  // aufgebaut wurde; sonst liefe es nur minimiert weiter.
  final navigator = Navigator.of(context, rootNavigator: true);
  var start = _pendingStart;
  if (start == null) {
    final created = _resolveWorkout(
      navigator,
      repository: repository,
      activeWorkout: activeWorkout,
      planId: planId,
    );
    start = created;
    _pendingStart = created;
    created.whenComplete(() {
      if (identical(_pendingStart, created)) _pendingStart = null;
    }).ignore();
  }
  final workoutId = await start;
  if (workoutId == null || !navigator.mounted) return;
  // Ein bereits offenes Training kommt nach vorn statt doppelt.
  await openWorkoutScreen(
    navigator.context,
    repository: repository,
    activeWorkout: activeWorkout,
    workoutId: workoutId,
  );
}

/// Liefert das zu öffnende Training oder null, wenn nichts geöffnet wird.
Future<String?> _resolveWorkout(
  NavigatorState navigator, {
  required TrainingLogRepository repository,
  required ActiveWorkoutController activeWorkout,
  required String planId,
}) async {
  final running = await repository.readActiveWorkout();
  if (!navigator.mounted) return null;

  String workoutId;
  if (running != null) {
    final resume = await showGainerStackedDialog<bool>(
      context: navigator.context,
      title: 'Aktives Training',
      message:
          'Es kann nur ein aktives Training geben. „${running.title}“ läuft noch.',
      actions: const [
        GainerDialogAction(label: 'Aktives Training fortsetzen', value: true),
        GainerDialogAction(label: 'Abbrechen', value: false),
      ],
    );
    if (resume != true) return null;
    workoutId = running.workoutId;
  } else {
    try {
      workoutId = (await repository.startFromPlan(planId)).workoutId;
    } on ActiveWorkoutExistsException catch (error) {
      workoutId = error.workoutId;
    } catch (error) {
      if (navigator.mounted) {
        await showGainerStackedDialog<bool>(
          context: navigator.context,
          title: 'Training nicht gestartet',
          message: planErrorMessage(
            error,
            'Das Training konnte nicht gestartet werden. Es wurde nichts gespeichert.',
          ),
          actions: const [GainerDialogAction(label: 'OK', value: true)],
        );
      }
      return null;
    }
  }

  await activeWorkout.load();
  return workoutId;
}
