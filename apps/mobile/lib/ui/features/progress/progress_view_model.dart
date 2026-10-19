import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';
import '../../../data/repositories/nutrition/nutrition_repository.dart';

class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel(this.repository, {this.nutrition, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final InsightsRepository repository;

  /// Lokale Ernährungsdaten für die Kalorien von heute (offline verfügbar).
  final NutritionRepository? nutrition;
  final DateTime Function() _now;

  /// Kalorien und Protein des lokalen heutigen Tages; `null`, solange sie
  /// nicht gelesen werden konnten.
  double? todayCaloriesKcal;
  double? todayProteinGrams;
  ApiDashboardInsights? dashboard;
  bool isLoading = false;
  bool dashboardIsStale = false;
  DateTime? dashboardCachedAtUtc;
  int _dashboardRequest = 0;
  String? errorMessage;
  bool _disposed = false;

  /// Liest nur die lokalen Tageswerte neu, etwa wenn der Tab wieder sichtbar
  /// wird. Braucht keine Verbindung.
  Future<void> refreshToday() async {
    final repo = nutrition;
    if (repo == null || _disposed) return;
    final day = _now();
    final localDate =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    try {
      final totals = (await repo.read(localDate)).day.totals;
      if (_disposed) return;
      final kcal = totals.kilocalories;
      final protein = totals.proteinGrams;
      if (kcal == todayCaloriesKcal && protein == todayProteinGrams) return;
      todayCaloriesKcal = kcal;
      todayProteinGrams = protein;
      notifyListeners();
    } on Object {
      // Ein Lesefehler lässt den zuletzt gezeigten Wert stehen.
    }
  }

  Future<void> load() async {
    if (_disposed) return;
    unawaited(refreshToday());
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

  @override
  void dispose() {
    _disposed = true;
    ++_dashboardRequest;
    super.dispose();
  }
}
