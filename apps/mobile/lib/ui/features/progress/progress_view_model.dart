import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';

/// Dashboard-Daten (Gewichtsverlauf, Trainingsübersicht) vom Server mit
/// lokalem Cache. Die lokalen Tageswerte liest der Kalender selbst.
class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel(this.repository);

  final InsightsRepository repository;
  ApiDashboardInsights? dashboard;
  bool isLoading = false;
  bool dashboardIsStale = false;
  DateTime? dashboardCachedAtUtc;
  int _dashboardRequest = 0;
  String? errorMessage;
  bool _disposed = false;

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
