import 'package:flutter/foundation.dart';

import '../../../data/repositories/body/body_repository.dart';
import '../../../domain/models/body/body_tracking.dart';

class BodyViewModel extends ChangeNotifier {
  BodyViewModel(this.repository);

  final BodyRepository repository;
  BodyTrackingSnapshot? snapshot;
  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;

  /// Feldfehler der letzten Validierung, z. B. `weightKg` → Meldung.
  Map<String, String> fieldErrors = const {};
  bool _disposed = false;

  Future<void> load() => _run(() async {
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  });

  Future<void> saveGoal({
    required BodyGoalKind kind,
    required double startWeightKg,
    required double targetWeightKg,
    required String startDate,
    required String? targetDate,
  }) => _run(() async {
    await repository.activateGoal(
      kind: kind,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      startDate: startDate,
      targetDate: targetDate,
    );
    if (_disposed) return;
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  }, saving: true);

  Future<void> saveCheckIn({
    required String localDate,
    required double weightKg,
    double? caloriesKcal,
    double? proteinGrams,
    double? carbohydrateGrams,
    double? fatGrams,
    int? steps,
    int? sleepMinutes,
  }) => _run(() async {
    await repository.saveCheckIn(
      localDate: localDate,
      weightKg: weightKg,
      caloriesKcal: caloriesKcal,
      proteinGrams: proteinGrams,
      carbohydrateGrams: carbohydrateGrams,
      fatGrams: fatGrams,
      steps: steps,
      sleepMinutes: sleepMinutes,
    );
    if (_disposed) return;
    final loaded = await repository.read();
    if (_disposed) return;
    snapshot = loaded;
  }, saving: true);

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
  }) async {
    if (_disposed) return;
    isLoading = !saving;
    isSaving = saving;
    errorMessage = null;
    fieldErrors = const {};
    _notify();
    try {
      await action();
    } on BodyTrackingValidationException catch (error) {
      if (!_disposed) fieldErrors = Map.unmodifiable(error.fields);
    } catch (error) {
      if (!_disposed) errorMessage = error.toString();
    } finally {
      if (!_disposed) {
        isLoading = false;
        isSaving = false;
        _notify();
      }
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
