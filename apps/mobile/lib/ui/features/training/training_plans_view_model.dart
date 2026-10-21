import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/workout_validation.dart';

/// Hält Pläne und die Rhythmus-Vorschau für den Pläne-Tab.
class TrainingPlansViewModel extends ChangeNotifier {
  TrainingPlansViewModel({required this.repository});

  final TrainingLogRepository repository;

  /// Aktive Pläne in Nutzerreihenfolge.
  List<TrainingPlanModel> plans = const [];

  /// Vorschau des Rhythmus für heute; `schedule` ist null ohne Rhythmus.
  TrainingScheduleProjection? projection;

  /// Pläne, die im Rhythmus vorkommen.
  Set<String> get scheduledPlanIds => {
    for (final slot
        in projection?.schedule?.slots ?? const <TrainingScheduleSlot>[])
      ?slot.planId,
  };

  bool isLoading = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loadedPlans = await repository.readPlans();
      final loadedProjection = await repository.schedule.readProjection();
      if (_disposed) return;
      plans = loadedPlans;
      projection = loadedProjection;
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Pläne konnten nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Ordnet die Pläne neu. Liefert eine Fehlermeldung oder null bei Erfolg.
  Future<String?> reorder(List<String> planIdsInOrder) async {
    try {
      await repository.reorderPlans(planIdsInOrder);
    } catch (error) {
      await load();
      return planErrorMessage(
        error,
        'Die Reihenfolge konnte nicht gespeichert werden.',
      );
    }
    await load();
    return null;
  }

  /// Archiviert einen Plan. Liefert eine Fehlermeldung oder null bei Erfolg.
  Future<String?> archive(String planId) async {
    try {
      await repository.archivePlan(planId);
    } catch (error) {
      await load();
      return planErrorMessage(
        error,
        'Der Plan konnte nicht archiviert werden.',
      );
    }
    await load();
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Nutzertext zu einem Fehler aus dem Repository. Unbekannte Fehler erhalten [fallback].
String planErrorMessage(Object error, String fallback) => switch (error) {
  StateError(:final message) => message,
  WorkoutValidationException(:final fields) when fields.isNotEmpty =>
    fields.values.first,
  _ => fallback,
};
