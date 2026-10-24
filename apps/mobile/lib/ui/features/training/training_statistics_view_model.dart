import 'package:flutter/foundation.dart';

import '../../../data/repositories/cardio/cardio_repository.dart';
import '../../../data/repositories/sync/local_sync_store.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/body/body_tracking.dart';
import '../../../domain/models/cardio/cardio_session.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/training_heatmap.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../../domain/models/training/training_statistics.dart';
import '../../../domain/models/training/workout_model.dart';

const _includeWarmupsKey = 'trainingStatistics:includeWarmups';

/// Schalter „Aufwärmsätze einbeziehen“. Gerätelokal, kontogebunden, Standard aus.
Future<bool> readIncludeWarmupSets(LocalSyncStore store) async {
  final raw = await store.readSyncMetadata(_includeWarmupsKey);
  return raw is bool && raw;
}

Future<void> writeIncludeWarmupSets(LocalSyncStore store, bool value) =>
    store.writeSyncMetadata(_includeWarmupsKey, value);

/// Eingaben aller Kennzahlen: beendete, nicht gelöschte Trainings in
/// chronologischer Reihenfolge sowie Check-ins und Katalog für die Gewichte.
typedef StatisticsInputs = ({
  List<Workout> workouts,
  List<DailyCheckIn> checkIns,
  List<CatalogExercise> catalog,
});

Future<StatisticsInputs> loadStatisticsInputs(
  TrainingLogRepository repository,
) async {
  final workouts =
      [
        for (final workout in await repository.readDiary())
          if (isCountedWorkout(workout)) workout,
      ]..sort((a, b) {
        final byStart = a.startedAtUtc.compareTo(b.startedAtUtc);
        return byStart == 0 ? a.workoutId.compareTo(b.workoutId) : byStart;
      });
  return (
    workouts: workouts,
    checkIns: await repository.readCheckIns(),
    catalog: await repository.readExercises(includeArchived: true),
  );
}

/// Eine trainierte Übung mit ihrem aktuellen Rekord für die Statistikliste.
class TrainedExerciseSummary {
  const TrainedExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.lastTrainedAtUtc,
    required this.estimatedOneRepMaxKg,
    required this.maxWeightKg,
  });

  final String exerciseId;

  /// Name aus dem jüngsten Training, damit die Liste auch ohne Katalog stimmt.
  final String name;
  final DateTime lastTrainedAtUtc;
  final double? estimatedOneRepMaxKg;
  final double? maxWeightKg;
}

/// Nur Übungen mit mindestens einem gezählten Satz. Die Reihenfolge ist
/// „zuletzt trainiert“ zuerst, bei Gleichstand alphabetisch.
List<TrainedExerciseSummary> summarizeTrainedExercises(
  StatisticsInputs inputs, {
  required bool includeWarmups,
}) {
  final totals = exerciseTotalsPerWorkout(
    inputs.workouts,
    checkIns: inputs.checkIns,
    catalog: inputs.catalog,
    includeWarmups: includeWarmups,
  );
  final records = exerciseRecords(
    inputs.workouts,
    checkIns: inputs.checkIns,
    catalog: inputs.catalog,
    includeWarmups: includeWarmups,
  );
  final summaries = [
    for (final entry in totals.entries)
      TrainedExerciseSummary(
        exerciseId: entry.key,
        name: entry.value.last.exerciseName,
        lastTrainedAtUtc: entry.value.last.startedAtUtc,
        estimatedOneRepMaxKg:
            records[entry.key]?.estimatedOneRepMax.lastOrNull?.value,
        maxWeightKg: records[entry.key]?.maxWeight.lastOrNull?.value,
      ),
  ];
  summaries.sort((a, b) {
    final byDate = b.lastTrainedAtUtc.compareTo(a.lastTrainedAtUtc);
    return byDate != 0 ? byDate : a.name.compareTo(b.name);
  });
  return summaries;
}

/// Heatmap der letzten 12 Monate aus gezählten Trainings und Cardio-Einheiten
/// (aus [CardioRepository.readSessions], also ohne gelöschte).
TrainingHeatmap trainingHeatmapOf(
  List<Workout> countedWorkouts,
  List<CardioSession> cardioSessions, {
  required LocalDay today,
}) {
  return buildTrainingHeatmap([
    for (final workout in countedWorkouts)
      if (workout.endedAtUtc case final ended?)
        (startedAtUtc: workout.startedAtUtc, endedAtUtc: ended),
    for (final session in cardioSessions)
      (startedAtUtc: session.startedAtUtc, endedAtUtc: session.endedAtUtc),
  ], today: today);
}

/// Liste der trainierten Übungen mit Suche und Aufwärmsatz-Schalter sowie
/// die Heatmap der Trainingstage.
class TrainingStatisticsViewModel extends ChangeNotifier {
  TrainingStatisticsViewModel({required this.repository, this.cardio});

  final TrainingLogRepository repository;

  /// Cardio-Einheiten für die Heatmap; ohne Wert zählt nur Krafttraining.
  final CardioRepository? cardio;

  List<TrainedExerciseSummary> exercises = const [];

  /// Null, solange nicht geladen oder wenn die Einheiten nicht lesbar sind.
  TrainingHeatmap? heatmap;
  bool includeWarmups = false;
  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;
  String _query = '';
  bool _disposed = false;

  String get query => _query;

  /// Trainierte Übungen, deren Name die Suche enthält.
  List<TrainedExerciseSummary> get visibleExercises {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return exercises;
    return [
      for (final exercise in exercises)
        if (exercise.name.toLowerCase().contains(needle)) exercise,
    ];
  }

  void setQuery(String value) {
    _query = value;
    _notify();
  }

  /// Lädt Übungen und Heatmap.
  Future<void> load() => _load(withHeatmap: true);

  Future<void> _load({required bool withHeatmap}) async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      includeWarmups = await readIncludeWarmupSets(repository.store);
      final inputs = await loadStatisticsInputs(repository);
      if (_disposed) return;
      exercises = summarizeTrainedExercises(
        inputs,
        includeWarmups: includeWarmups,
      );
      if (withHeatmap) {
        final sessions = await _readCardioSessions();
        if (_disposed) return;
        // Ohne lesbare Cardio-Einheiten wäre die Heatmap unvollständig.
        heatmap = sessions == null
            ? null
            : trainingHeatmapOf(
                inputs.workouts,
                sessions,
                today: repository.schedule.today(),
              );
      }
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Statistik konnte nicht berechnet werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        hasLoaded = true;
        _notify();
      }
    }
  }

  /// Cardio-Einheiten für die Heatmap; ohne [cardio] keine. Sind sie nicht
  /// lesbar, wird der Fehler gemeldet und das Ergebnis ist `null`.
  Future<List<CardioSession>?> _readCardioSessions() async {
    final cardio = this.cardio;
    if (cardio == null) return const [];
    try {
      return await cardio.readSessions();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Trainingsstatistik',
          context: ErrorDescription(
            'beim Lesen der Cardio-Einheiten für die Heatmap',
          ),
        ),
      );
      return null;
    }
  }

  /// Speichert den Schalter und berechnet nur die Übungen neu; Cardio und
  /// Heatmap hängen nicht von Aufwärmsätzen ab.
  Future<void> setIncludeWarmups(bool value) async {
    await writeIncludeWarmupSets(repository.store, value);
    await _load(withHeatmap: false);
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
