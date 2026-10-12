import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';

class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel(this.repository);

  final InsightsRepository repository;
  ApiDashboardInsights? dashboard;
  bool isLoading = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.loadDashboard();
      if (_disposed) return;
      dashboard = result;
    } catch (_) {
      if (_disposed) return;
      errorMessage =
          'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
