import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';
import '../../../data/repositories/training/api_exercise_catalog_provider.dart';
import '../../../data/repositories/training/training_repository.dart';

class ExerciseProgressOption {
  const ExerciseProgressOption({
    required this.id,
    required this.name,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final bool isCustom;
}

class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel(this.repository, {this.trainingRepository});

  static const progressWindows = ['7', '30', '90', 'all'];

  final InsightsRepository repository;
  final TrainingRepository? trainingRepository;
  ApiDashboardInsights? dashboard;
  bool isLoading = false;
  bool dashboardIsStale = false;
  DateTime? dashboardCachedAtUtc;
  int _dashboardRequest = 0;
  String? errorMessage;
  bool _disposed = false;

  List<ExerciseProgressOption> exerciseOptions = const [];
  String? selectedExerciseId;
  String selectedProgressWindow = '30';
  ApiExerciseProgress? exerciseProgress;
  bool isLoadingExerciseOptions = false;
  bool isLoadingExerciseProgress = false;
  bool isExerciseProgressStale = false;
  bool isExerciseCatalogStale = false;
  DateTime? exerciseProgressCachedAtUtc;
  String? exerciseProgressErrorMessage;
  String? exerciseOptionsErrorMessage;
  int _exerciseOptionsRequest = 0;
  int _exerciseProgressRequest = 0;
  bool _hasLoadedExerciseOptions = false;

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_dashboardRequest;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    CachedDashboardInsights? cached;
    try {
      cached = await repository.readCachedDashboard();
    } on Object {
      // A cache read failure does not block the server request.
    }
    if (_disposed || request != _dashboardRequest) return;
    if (cached != null) {
      dashboard = cached.value;
      dashboardCachedAtUtc = cached.cachedAtUtc;
      dashboardIsStale = true;
      notifyListeners();
    }
    try {
      final result = await repository.loadDashboard();
      if (_disposed || request != _dashboardRequest) return;
      dashboard = result;
      dashboardCachedAtUtc = DateTime.now().toUtc();
      dashboardIsStale = false;
      try {
        await repository.cacheDashboard(value: result);
      } on Object {
        // A cache-write failure must not discard a valid server response.
      }
    } catch (_) {
      if (_disposed || request != _dashboardRequest) return;
      if (dashboard != null) dashboardIsStale = true;
      if (cached == null && dashboard == null) {
        errorMessage = 'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.';
      } else {
        errorMessage = 'Fortschritt konnte nicht aktualisiert werden; gespeicherte Werte bleiben sichtbar.';
      }
    } finally {
      if (!_disposed && request == _dashboardRequest) {
        isLoading = false;
        notifyListeners();
      }
    }
    unawaited(loadExerciseOptions(refresh: true));
  }

  Future<void> loadExerciseOptions({bool refresh = false}) async {
    final training = trainingRepository;
    if (_disposed ||
        training == null ||
        (isLoadingExerciseOptions || (_hasLoadedExerciseOptions && !refresh))) {
      return;
    }
    final request = ++_exerciseOptionsRequest;
    isLoadingExerciseOptions = true;
    exerciseOptionsErrorMessage = null;
    notifyListeners();
    try {
      final planning = await training.readPlanning();
      if (_disposed || request != _exerciseOptionsRequest) return;
      final options = <ExerciseProgressOption>[
        for (final exercise in planning.exercises)
          ExerciseProgressOption(id: exercise.id, name: exercise.name),
        for (final exercise in planning.customExercises)
          if (!exercise.isArchived)
            ExerciseProgressOption(
              id: exercise.id,
              name: exercise.value.name,
              isCustom: true,
            ),
      ];
      final byId = <String, ExerciseProgressOption>{};
      for (final option in options) {
        byId.putIfAbsent(option.id.toLowerCase(), () => option);
      }
      exerciseOptions = List.unmodifiable(byId.values);
      isExerciseCatalogStale =
          training.catalog is ApiExerciseCatalogProvider &&
          (training.catalog as ApiExerciseCatalogProvider).lastLoadWasStale;
      _hasLoadedExerciseOptions = true;
      final oldSelection = selectedExerciseId;
      final selectionExists =
          oldSelection != null &&
          exerciseOptions.any((item) => item.id == oldSelection);
      selectedExerciseId = selectionExists
          ? oldSelection
          : (exerciseOptions.isEmpty ? null : exerciseOptions.first.id);
      if (selectedExerciseId != oldSelection) {
        _clearExerciseProgress();
      }
      notifyListeners();
      if (selectedExerciseId != null &&
          (selectedExerciseId != oldSelection || exerciseProgress == null)) {
        unawaited(loadSelectedExerciseProgress());
      }
    } catch (_) {
      if (_disposed || request != _exerciseOptionsRequest) return;
      exerciseOptionsErrorMessage =
          'Übungen sind gerade nicht verfügbar. Bitte verbinde dich erneut.';
    } finally {
      if (!_disposed && request == _exerciseOptionsRequest) {
        isLoadingExerciseOptions = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectExercise(String exerciseId) async {
    if (_disposed ||
        !exerciseOptions.any((option) => option.id == exerciseId) ||
        exerciseId == selectedExerciseId) {
      return;
    }
    selectedExerciseId = exerciseId;
    _clearExerciseProgress();
    notifyListeners();
    await loadSelectedExerciseProgress();
  }

  Future<void> selectProgressWindow(String window) async {
    if (_disposed ||
        !progressWindows.contains(window) ||
        window == selectedProgressWindow) {
      return;
    }
    selectedProgressWindow = window;
    _clearExerciseProgress();
    notifyListeners();
    await loadSelectedExerciseProgress();
  }

  Future<void> loadSelectedExerciseProgress({bool refresh = false}) async {
    final exerciseId = selectedExerciseId;
    if (_disposed || exerciseId == null) return;
    final window = selectedProgressWindow;
    final request = ++_exerciseProgressRequest;
    isLoadingExerciseProgress = true;
    exerciseProgressErrorMessage = null;
    notifyListeners();

    CachedExerciseProgress? cached;
    if (!refresh) {
      try {
        cached = await repository.readCachedExerciseProgress(
          exerciseId: exerciseId,
          window: window,
        );
      } on Object {
        // An unavailable local cache does not block a fresh request.
      }
    }
    if (_disposed || request != _exerciseProgressRequest) return;
    if (cached != null) {
      exerciseProgress = cached.value;
      exerciseProgressCachedAtUtc = cached.cachedAtUtc;
      isExerciseProgressStale = true;
      notifyListeners();
    }

    try {
      final fresh = await repository.loadExerciseProgress(
        exerciseId: exerciseId,
        window: window,
      );
      if (_disposed || request != _exerciseProgressRequest) return;
      if (fresh.exerciseId.toLowerCase() != exerciseId.toLowerCase() ||
          !_responseMatchesWindow(fresh.windowDays, window)) {
        throw const FormatException('Exercise progress response mismatch.');
      }
      if (_disposed || request != _exerciseProgressRequest) return;
      exerciseProgress = fresh;
      exerciseProgressCachedAtUtc = DateTime.now().toUtc();
      isExerciseProgressStale = false;
      try {
        await repository.cacheExerciseProgress(
          exerciseId: exerciseId,
          window: window,
          value: fresh,
        );
      } on Object {
        // A local cache-write failure must not hide a valid server response.
      }
    } catch (_) {
      if (_disposed || request != _exerciseProgressRequest) return;
      if (exerciseProgress != null) {
        isExerciseProgressStale = true;
      } else if (cached == null) {
        exerciseProgressErrorMessage = 'Übungsfortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.';
      }
    } finally {
      if (!_disposed && request == _exerciseProgressRequest) {
        isLoadingExerciseProgress = false;
        notifyListeners();
      }
    }
  }

  void _clearExerciseProgress() {
    ++_exerciseProgressRequest;
    exerciseProgress = null;
    exerciseProgressCachedAtUtc = null;
    isExerciseProgressStale = false;
    exerciseProgressErrorMessage = null;
    isLoadingExerciseProgress = false;
  }

  bool _responseMatchesWindow(int? windowDays, String window) =>
      window == 'all' ? windowDays == null : windowDays == int.parse(window);

  @override
  void dispose() {
    _disposed = true;
    ++_dashboardRequest;
    ++_exerciseOptionsRequest;
    ++_exerciseProgressRequest;
    super.dispose();
  }
}
