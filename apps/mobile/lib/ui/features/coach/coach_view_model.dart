import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/insights/insights_repository.dart';

class CoachViewModel extends ChangeNotifier {
  CoachViewModel(this.repository);
  final CoachRepository repository;
  ApiCoachResponse? response;
  bool isLoading = false;
  String? errorMessage;

  Future<void> ask(String question) async {
    if (question.trim().isEmpty || question.length > 1000) {
      errorMessage = 'Gib eine Frage mit höchstens 1000 Zeichen ein.';
      notifyListeners();
      return;
    }
    isLoading = true;
    errorMessage = null;
    response = null;
    notifyListeners();
    try {
      response = await repository.ask(question.trim());
    } catch (_) {
      errorMessage = 'Der Coach ist gerade nicht verfügbar. Deine Frage wurde nicht gespeichert.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
