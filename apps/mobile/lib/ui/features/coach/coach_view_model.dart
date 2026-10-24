import 'package:flutter/foundation.dart';

import '../../../data/models/api/api_models.dart';
import '../../../data/repositories/coach/coach_memory_repository.dart';
import '../../../data/repositories/insights/insights_repository.dart';

/// Zustand eines Gedächtnis-Vorschlags unter einer Coach-Antwort.
enum CoachSuggestionState { open, saving, saved, dismissed }

class CoachViewModel extends ChangeNotifier {
  CoachViewModel(this.repository, {this.memories, this.online = true});
  final CoachRepository repository;

  /// Null, wenn das Konto kein Gedächtnis anbietet (z. B. in alten Tests).
  final CoachMemoryRepository? memories;

  /// Das Konto wurde mit Verbindung geöffnet.
  final bool online;
  ApiCoachResponse? response;
  bool isLoading = false;
  String? errorMessage;
  bool _disposed = false;
  final _suggestionStates = <int, CoachSuggestionState>{};
  final _suggestionErrors = <int, String>{};

  CoachSuggestionState suggestionState(int index) =>
      _suggestionStates[index] ?? CoachSuggestionState.open;

  String? suggestionError(int index) => _suggestionErrors[index];

  Future<void> ask(String question) async {
    if (_disposed) return;
    if (question.trim().isEmpty || question.length > 1000) {
      errorMessage = 'Gib eine Frage mit höchstens 1000 Zeichen ein.';
      notifyListeners();
      return;
    }
    isLoading = true;
    errorMessage = null;
    response = null;
    _suggestionStates.clear();
    _suggestionErrors.clear();
    notifyListeners();
    try {
      final result = await repository.ask(question.trim());
      if (_disposed) return;
      response = result;
    } catch (_) {
      if (_disposed) return;
      errorMessage = 'Der Coach ist gerade nicht verfügbar. Deine Frage wurde nicht gespeichert.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Speichert den Vorschlag [index] der aktuellen Antwort im Gedächtnis.
  Future<void> remember(int index) async {
    final store = memories;
    final answer = response;
    if (_disposed ||
        store == null ||
        answer == null ||
        index < 0 ||
        index >= answer.memorySuggestions.length ||
        suggestionState(index) != CoachSuggestionState.open) {
      return;
    }
    final suggestion = answer.memorySuggestions[index];
    _suggestionStates[index] = CoachSuggestionState.saving;
    _suggestionErrors.remove(index);
    notifyListeners();
    try {
      await store.create(suggestion.category, suggestion.text);
      if (_disposed || !identical(response, answer)) return;
      _suggestionStates[index] = CoachSuggestionState.saved;
    } on Object catch (error) {
      if (_disposed || !identical(response, answer)) return;
      _suggestionStates[index] = CoachSuggestionState.open;
      _suggestionErrors[index] = coachMemoryErrorMessage(error);
    }
    notifyListeners();
  }

  /// Blendet den Vorschlag [index] aus; gespeichert wird nichts.
  void dismiss(int index) {
    if (_disposed || suggestionState(index) != CoachSuggestionState.open) {
      return;
    }
    _suggestionStates[index] = CoachSuggestionState.dismissed;
    _suggestionErrors.remove(index);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
