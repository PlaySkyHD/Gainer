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

  /// Zuletzt bekannt: keine Verbindung. Eine erfolgreiche Anfrage hebt das auf.
  late bool memoryOffline = !online;

  /// Das Gedächtnis ist laut Liste oder `memory_limit_reached` voll.
  bool memoryFull = false;
  int? _memoryCount;
  int _memoryMax = 50;

  CoachSuggestionState suggestionState(int index) =>
      _suggestionStates[index] ?? CoachSuggestionState.open;

  String? suggestionError(int index) => _suggestionErrors[index];

  /// Grund, warum „Merken“ gerade nicht geht, sonst null.
  String? get rememberBlockedReason {
    if (memoryOffline) {
      return 'Keine Verbindung. „Merken“ geht erst wieder online.';
    }
    if (memoryFull) {
      return 'Das Gedächtnis ist voll. Lösche unter Gedächtnis eine Notiz, '
          'um Neues zu merken.';
    }
    return null;
  }

  bool get _hasOpenSuggestions {
    final answer = response;
    if (answer == null) return false;
    for (var i = 0; i < answer.memorySuggestions.length; i++) {
      if (suggestionState(i) == CoachSuggestionState.open) return true;
    }
    return false;
  }

  /// Liest Belegung und Höchstzahl des Gedächtnisses, damit „Merken“ bei
  /// vollem Gedächtnis gesperrt ist. Nur nötig, solange Vorschläge offen sind.
  Future<void> refreshMemoryUsage() async {
    final store = memories;
    if (_disposed || store == null || !_hasOpenSuggestions) return;
    try {
      final list = await store.list();
      if (_disposed) return;
      _memoryCount = list.items.length;
      _memoryMax = list.maxEntries;
      memoryFull = list.items.length >= list.maxEntries;
      memoryOffline = false;
    } on Object catch (error) {
      if (_disposed) return;
      if (isCoachMemoryOfflineError(error)) memoryOffline = true;
    }
    notifyListeners();
  }

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
    var answered = false;
    try {
      final result = await repository.ask(question.trim());
      if (_disposed) return;
      response = result;
      memoryOffline = false;
      answered = true;
    } catch (error) {
      if (_disposed) return;
      if (isCoachMemoryOfflineError(error)) memoryOffline = true;
      errorMessage = 'Der Coach ist gerade nicht verfügbar. Deine Frage wurde nicht gespeichert.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
    if (answered) await refreshMemoryUsage();
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
        suggestionState(index) != CoachSuggestionState.open ||
        rememberBlockedReason != null) {
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
      if (_memoryCount case final count?) {
        _memoryCount = count + 1;
        memoryFull = count + 1 >= _memoryMax;
      }
    } on Object catch (error) {
      if (_disposed || !identical(response, answer)) return;
      _suggestionStates[index] = CoachSuggestionState.open;
      // Offline und voll sperren alle Vorschläge; den Grund nennt der
      // Abschnitt einmal, nicht jede Zeile.
      if (isCoachMemoryOfflineError(error)) {
        memoryOffline = true;
      } else if (isCoachMemoryFullError(error)) {
        memoryFull = true;
      } else {
        _suggestionErrors[index] = coachMemoryErrorMessage(error);
      }
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
