import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_statistics.dart';
import '../../../domain/models/training/workout_input.dart';
import 'training_statistics_view_model.dart';

enum ChartMetric { estimatedOneRepMax, maxWeight, volume }

enum ChartPeriod { threeMonths, oneYear, all }

class ChartPoint {
  const ChartPoint({required this.startedAtUtc, required this.value});

  final DateTime startedAtUtc;
  final double value;
}

/// Statistik einer Übung: Trainings, Rekorde und Graph. Alles aus lokalen Daten
/// mit den Funktionen aus `training_statistics.dart`.
class ExerciseStatisticsViewModel extends ChangeNotifier {
  ExerciseStatisticsViewModel({
    required this.repository,
    required this.exerciseId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TrainingLogRepository repository;
  final String exerciseId;
  final DateTime Function() _clock;

  String? exerciseName;

  /// Trainings mit der Übung, chronologisch, älteste zuerst. Kennzahlen kommen
  /// aus der Domäne (`exerciseTotalsPerWorkout`).
  List<ExerciseWorkoutTotals> sessions = const [];
  final Map<String, String> _titles = {};
  ExerciseRecords? records;
  bool includeWarmups = false;

  /// Gewichtseinheit des Kontos für die Anzeige.
  WeightUnit weightUnit = WeightUnit.kg;
  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;
  ChartMetric metric = ChartMetric.estimatedOneRepMax;
  ChartPeriod period = ChartPeriod.all;
  bool _disposed = false;

  bool get bodyweightMissing =>
      sessions.any((session) => session.bodyweightMissing);

  /// Name des Trainings für die Anzeige im Verlauf.
  String titleOf(String workoutId) => _titles[workoutId] ?? '';

  /// Chronologische Punkte der gewählten Kennzahl im gewählten Zeitraum.
  List<ChartPoint> get chartPoints {
    final cutoff = _cutoff();
    return [
      for (final session in sessions)
        if (_valueFor(session, metric) case final value?)
          if (cutoff == null ||
              !session.startedAtUtc.toLocal().isBefore(cutoff))
            ChartPoint(startedAtUtc: session.startedAtUtc, value: value),
    ];
  }

  /// Datum, zu dem ein Rekordwert erzielt wurde.
  DateTime? recordDate(String workoutId) {
    for (final session in sessions) {
      if (session.workoutId == workoutId) return session.startedAtUtc;
    }
    return null;
  }

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      includeWarmups = await readIncludeWarmupSets(repository.store);
      weightUnit = await readStatisticsWeightUnit(repository.store);
      final inputs = await loadStatisticsInputs(repository);
      if (_disposed) return;
      _apply(inputs);
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

  Future<void> setIncludeWarmups(bool value) async {
    await writeIncludeWarmupSets(repository.store, value);
    await load();
  }

  void selectMetric(ChartMetric value) {
    metric = value;
    _notify();
  }

  void selectPeriod(ChartPeriod value) {
    period = value;
    _notify();
  }

  void _apply(StatisticsInputs inputs) {
    _titles
      ..clear()
      ..addEntries([
        for (final workout in inputs.workouts)
          MapEntry(workout.workoutId, workout.title),
      ]);
    final totals = exerciseTotalsPerWorkout(
      inputs.workouts,
      checkIns: inputs.checkIns,
      catalog: inputs.catalog,
      includeWarmups: includeWarmups,
    );
    sessions = totals[exerciseId] ?? const [];
    exerciseName = sessions.isEmpty ? null : sessions.last.exerciseName;
    records = exerciseRecords(
      inputs.workouts,
      checkIns: inputs.checkIns,
      catalog: inputs.catalog,
      includeWarmups: includeWarmups,
    )[exerciseId];
  }

  DateTime? _cutoff() {
    final now = _clock();
    return switch (period) {
      ChartPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
      ChartPeriod.oneYear => DateTime(now.year - 1, now.month, now.day),
      ChartPeriod.all => null,
    };
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

double? _valueFor(ExerciseWorkoutTotals session, ChartMetric metric) =>
    switch (metric) {
      ChartMetric.estimatedOneRepMax => session.estimatedOneRepMaxKg,
      ChartMetric.maxWeight => session.maxWeightKg,
      ChartMetric.volume => session.volumeKg,
    };
