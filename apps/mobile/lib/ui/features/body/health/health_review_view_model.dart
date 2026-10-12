import 'package:flutter/foundation.dart';

import '../../../../data/repositories/health/health_review_coordinator.dart';
import '../../../../data/services/platform/platform_ports.dart';

class HealthReviewViewModel extends ChangeNotifier {
  HealthReviewViewModel(this.coordinator);
  final HealthReviewCoordinator coordinator;
  HealthWeightReview? review;
  Set<String> selectedProbeIds = {};
  Set<String> replaceCheckInProbeIds = {};
  List<HealthImportReviewResult> lastResults = const [];
  List<CompletedWorkoutCandidate> completedWorkouts = const [];
  String? errorMessage;
  bool isLoading = false;
  bool serverSyncNoticeAccepted = false;

  Future<void> load() => _run(() async {
    completedWorkouts = await coordinator.completedWorkoutsForExport();
  });

  Future<void> prepareReview({
    required String fromLocalDate,
    required String toLocalDate,
  }) => _run(() async {
    review = await coordinator.prepareWeightReview(
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
    );
    selectedProbeIds = review!.samples.map((sample) => sample.uuid).toSet();
    replaceCheckInProbeIds = {};
    lastResults = const [];
    serverSyncNoticeAccepted = false;
  });

  void selectSample(String uuid, bool selected) {
    selectedProbeIds = {...selectedProbeIds};
    if (selected) {
      selectedProbeIds.add(uuid);
    } else {
      selectedProbeIds.remove(uuid);
    }
    notifyListeners();
  }

  void acceptServerSyncNotice(bool accepted) {
    serverSyncNoticeAccepted = accepted;
    notifyListeners();
  }

  Future<List<HealthImportReviewResult>> confirmImport({
    Set<String> replaceExistingFor = const {},
    Set<String> skipFor = const {},
  }) async {
    final current = review;
    if (current == null) {
      throw StateError('Es gibt keine Health-Proben zur Prüfung.');
    }
    var result = const <HealthImportReviewResult>[];
    await _run(() async {
      result = await coordinator.confirmWeightReview(
        review: current,
        selectedProbeIds: selectedProbeIds,
        acceptedServerSyncNotice: serverSyncNoticeAccepted,
        replaceCheckInProbeIds: replaceExistingFor,
        skipCheckInProbeIds: skipFor,
      );
      lastResults = result;
      if (!result.any(
        (item) => item.status == HealthImportReviewStatus.dayConflict,
      )) {
        review = null;
        selectedProbeIds = {};
      }
    });
    return result;
  }

  Future<WorkoutExportReceipt?> exportWorkout(
    String workoutId, {
    required bool confirmed,
  }) async {
    WorkoutExportReceipt? receipt;
    await _run(() async {
      receipt = await coordinator.exportWorkout(
        workoutId: workoutId,
        userConfirmed: confirmed,
      );
    });
    return receipt;
  }

  void cancelReview() {
    review = null;
    selectedProbeIds = {};
    replaceCheckInProbeIds = {};
    serverSyncNoticeAccepted = false;
    lastResults = const [];
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
