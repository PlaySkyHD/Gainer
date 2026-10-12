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

  Future<void> load() => _run(() async {
    snapshot = await repository.read();
  });

  Future<void> saveGoal({
    required BodyGoalKind kind,
    required double startWeightKg,
    required double targetWeightKg,
    required String startDate,
    required String? targetDate,
  }) => _run(() async {
    isSaving = true;
    notifyListeners();
    await repository.activateGoal(
      kind: kind,
      startWeightKg: startWeightKg,
      targetWeightKg: targetWeightKg,
      startDate: startDate,
      targetDate: targetDate,
    );
    snapshot = await repository.read();
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
    snapshot = await repository.read();
  }, saving: true);

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
  }) async {
    isLoading = !saving;
    isSaving = saving;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      isSaving = false;
      notifyListeners();
    }
  }
}
