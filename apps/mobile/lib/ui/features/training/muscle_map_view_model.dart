import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/muscle_volume.dart';
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/workout_model.dart';

enum MuscleMapSource { planned, trained }

/// Zeitraum für „Trainiert“; 28 Tage zeigen den Ø pro Woche.
enum MuscleMapPeriod {
  week(7, 1),
  fourWeeks(28, 4);

  const MuscleMapPeriod(this.days, this.weeks);

  final int days;
  final int weeks;
}

/// Lädt Pläne, Trainings und Übungen und rechnet die Sätze je Muskel für die
/// gewählte Quelle (Design D3).
class MuscleMapViewModel extends ChangeNotifier {
  MuscleMapViewModel({required this.repository, String? initialPlanId})
    : _planId = initialPlanId;

  final TrainingLogRepository repository;

  List<TrainingPlanModel> plans = const [];
  List<Workout> _workouts = const [];
  Map<String, CatalogExercise> _exercises = const {};
  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;
  bool _disposed = false;

  MuscleMapSource _source = MuscleMapSource.planned;
  MuscleMapPeriod _period = MuscleMapPeriod.week;
  String? _planId;
  MuscleVolume? _volume;

  MuscleMapSource get source => _source;
  MuscleMapPeriod get period => _period;

  /// Gewählter Plan; `null` = alle aktiven Pläne.
  String? get planId => _planId;

  TrainingPlanModel? get selectedPlan {
    for (final plan in plans) {
      if (plan.planId == _planId) return plan;
    }
    return null;
  }

  MuscleVolume get volume => _volume ??= _compute();

  /// True, wenn die Übung bekannt ist und ihr Editor geöffnet werden kann.
  bool canOpenExercise(String exerciseId) => _exercises.containsKey(exerciseId);

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loadedPlans = await repository.readPlans();
      final workouts = await repository.readDiary();
      final exercises = await repository.readExercises(includeArchived: true);
      if (_disposed) return;
      plans = loadedPlans;
      _workouts = workouts;
      _exercises = {for (final exercise in exercises) exercise.id: exercise};
      if (selectedPlan == null) _planId = null;
      hasLoaded = true;
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Muskeln konnten nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _volume = null;
        _notify();
      }
    }
  }

  void setSource(MuscleMapSource source) => _update(() => _source = source);

  void setPeriod(MuscleMapPeriod period) => _update(() => _period = period);

  void selectPlan(String? planId) => _update(() => _planId = planId);

  void _update(VoidCallback change) {
    change();
    _volume = null;
    _notify();
  }

  MuscleVolume _compute() {
    if (!hasLoaded) return MuscleVolume.empty;
    switch (_source) {
      case MuscleMapSource.planned:
        final plan = selectedPlan;
        return MuscleVolume.fromPlans(
          plan == null ? plans : [plan],
          _exercises,
        );
      case MuscleMapSource.trained:
        final now = repository.nowUtc();
        return MuscleVolume.fromWorkouts(
          _workouts,
          _exercises,
          fromUtc: now.subtract(Duration(days: _period.days)),
          toUtc: now,
          weeks: _period.weeks,
        );
    }
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
