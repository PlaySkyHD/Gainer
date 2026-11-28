import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/training_analysis.dart';
import '../../../domain/models/training/training_trends.dart';
import '../../../domain/models/training/workout_input.dart';
import 'training_statistics_view_model.dart';

/// Lädt die Trainings aus dem lokalen Speicher und rechnet die
/// Trainingsanalyse für den gewählten Zeitraum (offline, wie die Statistik).
class TrainingAnalysisViewModel extends ChangeNotifier {
  TrainingAnalysisViewModel({required this.repository});

  final TrainingLogRepository repository;

  TrendPeriod period = TrendPeriod.threeMonths;

  /// Null, solange nicht geladen.
  TrainingAnalysis? analysis;
  WeightUnit weightUnit = WeightUnit.kg;
  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;
  StatisticsInputs? _inputs;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    weightUnit = await readStatisticsWeightUnit(repository.preferences);
    try {
      final inputs = await loadStatisticsInputs(repository);
      if (_disposed) return;
      _inputs = inputs;
      _compute();
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Trainingsanalyse konnte nicht berechnet werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        hasLoaded = true;
        _notify();
      }
    }
  }

  /// Wechselt den Zeitraum; die Trainings bleiben geladen.
  void selectPeriod(TrendPeriod value) {
    if (value == period) return;
    period = value;
    if (_inputs != null) _compute();
    _notify();
  }

  void _compute() {
    final inputs = _inputs!;
    analysis = TrainingAnalysis.compute(
      inputs.workouts,
      checkIns: inputs.checkIns,
      catalog: inputs.catalog,
      period: period,
      today: repository.schedule.today(),
    );
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
