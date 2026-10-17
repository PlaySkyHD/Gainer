import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';

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
  ProgressViewModel(this.repository, {this.training});

  static const progressWindows = ['7', '30', '90', 'all'];

  final InsightsRepository repository;
  final TrainingLogRepository? training;
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
    final cached = await _readCachedDashboard();
    if (!_isCurrentDashboardRequest(request)) return;
    if (cached != null) {
      dashboard = cached.value;
      dashboardCachedAtUtc = cached.cachedAtUtc;
      dashboardIsStale = true;
      notifyListeners();
    }
    try {
      final result = await repository.loadDashboard();
      if (!_isCurrentDashboardRequest(request)) return;
      dashboard = result;
      dashboardCachedAtUtc = DateTime.now().toUtc();
      dashboardIsStale = false;
      await _cacheDashboardQuietly(result);
    } catch (_) {
      if (!_isCurrentDashboardRequest(request)) return;
      if (dashboard != null) dashboardIsStale = true;
      errorMessage = _dashboardErrorMessage(cached);
    } finally {
      if (_isCurrentDashboardRequest(request)) {
        isLoading = false;
        notifyListeners();
      }
    }
    unawaited(loadExerciseOptions(refresh: true));
  }

  Future<void> loadExerciseOptions({bool refresh = false}) async {
    final trainingLog = training;
    if (_disposed ||
        trainingLog == null ||
        _isExerciseOptionsLoadRedundant(refresh)) {
      return;
    }
    final request = ++_exerciseOptionsRequest;
    isLoadingExerciseOptions = true;
    exerciseOptionsErrorMessage = null;
    notifyListeners();
    try {
      final exercises = await trainingLog.readExercises();
      if (!_isCurrentExerciseOptionsRequest(request)) return;
      exerciseOptions = _uniqueExerciseOptions(exercises);
      isExerciseCatalogStale = trainingLog.isCatalogStale;
      _hasLoadedExerciseOptions = true;
      final oldSelection = selectedExerciseId;
      selectedExerciseId = _selectionAfterOptionsLoad(oldSelection);
      if (selectedExerciseId != oldSelection) {
        _clearExerciseProgress();
      }
      notifyListeners();
      if (_shouldLoadSelectedProgress(oldSelection)) {
        unawaited(loadSelectedExerciseProgress());
      }
    } catch (_) {
      if (!_isCurrentExerciseOptionsRequest(request)) return;
      exerciseOptionsErrorMessage =
          'Übungen sind gerade nicht verfügbar. Bitte verbinde dich erneut.';
    } finally {
      if (_isCurrentExerciseOptionsRequest(request)) {
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

    final cached = refresh
        ? null
        : await _readCachedExerciseProgress(exerciseId, window);
    if (!_isCurrentExerciseProgressRequest(request)) return;
    if (cached != null) {
      exerciseProgress = cached.value;
      exerciseProgressCachedAtUtc = cached.cachedAtUtc;
      isExerciseProgressStale = true;
      notifyListeners();
    }
    await _fetchExerciseProgress(
      exerciseId: exerciseId,
      window: window,
      request: request,
      cached: cached,
    );
  }

  Future<CachedDashboardInsights?> _readCachedDashboard() async {
    try {
      return await repository.readCachedDashboard();
    } on Object {
      // A cache read failure does not block the server request.
      return null;
    }
  }

  Future<void> _cacheDashboardQuietly(ApiDashboardInsights value) async {
    try {
      await repository.cacheDashboard(value: value);
    } on Object {
      // A cache-write failure must not discard a valid server response.
    }
  }

  String _dashboardErrorMessage(CachedDashboardInsights? cached) =>
      cached == null && dashboard == null
      ? 'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.'
      : 'Fortschritt konnte nicht aktualisiert werden; gespeicherte Werte bleiben sichtbar.';

  bool _isCurrentDashboardRequest(int request) =>
      !_disposed && request == _dashboardRequest;

  bool _isExerciseOptionsLoadRedundant(bool refresh) =>
      isLoadingExerciseOptions || (_hasLoadedExerciseOptions && !refresh);

  bool _isCurrentExerciseOptionsRequest(int request) =>
      !_disposed && request == _exerciseOptionsRequest;

  List<ExerciseProgressOption> _uniqueExerciseOptions(
    List<CatalogExercise> exercises,
  ) {
    final options = <ExerciseProgressOption>[
      for (final exercise in exercises)
        ExerciseProgressOption(
          id: exercise.id,
          name: exercise.name,
          isCustom: !exercise.isBase,
        ),
    ];
    final byId = <String, ExerciseProgressOption>{};
    for (final option in options) {
      byId.putIfAbsent(option.id.toLowerCase(), () => option);
    }
    return List.unmodifiable(byId.values);
  }

  String? _selectionAfterOptionsLoad(String? oldSelection) {
    final selectionExists =
        oldSelection != null &&
        exerciseOptions.any((item) => item.id == oldSelection);
    if (selectionExists) return oldSelection;
    return exerciseOptions.isEmpty ? null : exerciseOptions.first.id;
  }

  bool _shouldLoadSelectedProgress(String? oldSelection) =>
      selectedExerciseId != null &&
      (selectedExerciseId != oldSelection || exerciseProgress == null);

  Future<CachedExerciseProgress?> _readCachedExerciseProgress(
    String exerciseId,
    String window,
  ) async {
    try {
      return await repository.readCachedExerciseProgress(
        exerciseId: exerciseId,
        window: window,
      );
    } on Object {
      // An unavailable local cache does not block a fresh request.
      return null;
    }
  }

  Future<void> _fetchExerciseProgress({
    required String exerciseId,
    required String window,
    required int request,
    required CachedExerciseProgress? cached,
  }) async {
    try {
      final fresh = await repository.loadExerciseProgress(
        exerciseId: exerciseId,
        window: window,
      );
      if (!_isCurrentExerciseProgressRequest(request)) return;
      if (_isMismatchedExerciseProgress(fresh, exerciseId, window)) {
        throw const FormatException('Exercise progress response mismatch.');
      }
      exerciseProgress = fresh;
      exerciseProgressCachedAtUtc = DateTime.now().toUtc();
      isExerciseProgressStale = false;
      await _cacheExerciseProgressQuietly(exerciseId, window, fresh);
    } catch (_) {
      if (!_isCurrentExerciseProgressRequest(request)) return;
      _markExerciseProgressFailure(cached);
    } finally {
      if (_isCurrentExerciseProgressRequest(request)) {
        isLoadingExerciseProgress = false;
        notifyListeners();
      }
    }
  }

  Future<void> _cacheExerciseProgressQuietly(
    String exerciseId,
    String window,
    ApiExerciseProgress value,
  ) async {
    try {
      await repository.cacheExerciseProgress(
        exerciseId: exerciseId,
        window: window,
        value: value,
      );
    } on Object {
      // A local cache-write failure must not hide a valid server response.
    }
  }

  void _markExerciseProgressFailure(CachedExerciseProgress? cached) {
    if (exerciseProgress != null) {
      isExerciseProgressStale = true;
    } else if (cached == null) {
      exerciseProgressErrorMessage = 'Übungsfortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.';
    }
  }

  bool _isCurrentExerciseProgressRequest(int request) =>
      !_disposed && request == _exerciseProgressRequest;

  bool _isMismatchedExerciseProgress(
    ApiExerciseProgress progress,
    String exerciseId,
    String window,
  ) =>
      progress.exerciseId.toLowerCase() != exerciseId.toLowerCase() ||
      !_responseMatchesWindow(progress.windowDays, window);

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
