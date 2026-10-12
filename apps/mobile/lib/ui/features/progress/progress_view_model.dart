import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';

class ProgressViewModel extends ChangeNotifier {
  ProgressViewModel(this.repository);

  final InsightsRepository repository;
  ApiDashboardInsights? dashboard;
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      dashboard = await repository.loadDashboard();
    } catch (_) {
      errorMessage =
          'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
