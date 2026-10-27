import 'package:flutter/foundation.dart';

import '../../../data/models/api/coach_memory_api_models.dart';
import '../../../data/repositories/coach/coach_memory_repository.dart';

/// Grund, warum [CoachMemoryViewModel.save] nichts gespeichert hat.
class CoachMemorySaveFailure {
  const CoachMemorySaveFailure(this.message, {this.entryGone = false});

  final String message;

  /// Die bearbeitete Notiz gibt es auf dem Server nicht mehr. Erneut gegen
  /// ihre ID zu sichern ist sinnlos; das Sheet legt sie stattdessen neu an.
  final bool entryGone;
}

/// Liste und Änderungen des Coach-Gedächtnisses. Änderungen gehen nur, wenn
/// die Liste online geladen wurde und keine andere Änderung läuft.
class CoachMemoryViewModel extends ChangeNotifier {
  CoachMemoryViewModel(this.repository, {this.online = true});

  final CoachMemoryRepository repository;

  /// Das Konto wurde mit Verbindung geöffnet. Ohne Verbindung lädt der Screen
  /// nicht von selbst, bietet aber erneutes Laden an.
  final bool online;

  List<ApiCoachMemory> items = const [];
  int maxEntries = 50;
  bool isLoading = false;
  bool isBusy = false;

  /// Die Liste stammt vom Server; erst dann sind Änderungen möglich.
  bool isLoaded = false;

  /// Die letzte Anfrage scheiterte an fehlender Verbindung.
  bool isOffline = false;

  /// Grund, warum die Liste nicht geladen werden konnte.
  String? loadError;

  /// Fehler der letzten Änderung.
  String? actionError;
  bool _disposed = false;

  bool get canEdit => isLoaded && !isOffline && !isBusy;
  bool get isFull => items.length >= maxEntries;
  bool get canAdd => canEdit && !isFull;

  /// Notizen nach Kategorie in fester Reihenfolge, je Gruppe neueste zuerst.
  List<(CoachMemoryCategory, List<ApiCoachMemory>)> get groups => [
    for (final category in CoachMemoryCategory.values)
      if (items.where((item) => item.category == category).toList()
          case final entries when entries.isNotEmpty)
        (category, entries),
  ];

  /// Lädt beim Öffnen, sofern das Konto online geöffnet wurde.
  Future<void> start() async {
    if (online) {
      await load();
    } else {
      isOffline = true;
      loadError = _offlineReason;
      _notify();
    }
  }

  /// Lädt die Liste. True, wenn sie jetzt frisch vom Server stammt.
  Future<bool> load() async {
    if (_disposed || isLoading) return false;
    isLoading = true;
    loadError = null;
    actionError = null;
    _notify();
    try {
      final result = await repository.list();
      if (_disposed) return false;
      items = result.items;
      maxEntries = result.maxEntries;
      isLoaded = true;
      isOffline = false;
      return true;
    } on Object catch (error) {
      if (_disposed) return false;
      isOffline = isCoachMemoryOfflineError(error);
      loadError = isOffline
          ? _offlineReason
          : 'Das Gedächtnis konnte nicht geladen werden. Versuche es erneut.';
      return false;
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Legt eine Notiz an ([id] null) oder ändert sie. Liefert null bei Erfolg,
  /// sonst den Grund; das Notiz-Sheet zeigt ihn und bleibt dafür offen.
  /// Wurde die Notiz anderswo geändert oder gelöscht oder ist das Gedächtnis
  /// voll, lädt die Liste neu. Eine unbekannte Kategorie geht unverändert
  /// zurück, solange [category] die angezeigte geblieben ist.
  Future<CoachMemorySaveFailure?> save({
    String? id,
    required CoachMemoryCategory category,
    required String text,
  }) async {
    Object? failure;
    final saved = await _change(
      () async => _put(await _write(id, category, text)),
      onError: (error) => failure = error,
    );
    if (saved) return null;
    final error = failure;
    if (error == null) {
      return CoachMemorySaveFailure(isOffline ? _offlineReason : _busyReason);
    }
    return _saveFailure(error, id: id);
  }

  Future<ApiCoachMemory> _write(
    String? id,
    CoachMemoryCategory category,
    String text,
  ) {
    if (id == null) return repository.create(category, text);
    final base = items.where((item) => item.id == id).firstOrNull;
    return repository.update(
      id,
      category,
      text,
      baseVersion: base?.version,
      unknownCategory: base?.category == category
          ? base?.unknownCategory
          : null,
    );
  }

  Future<CoachMemorySaveFailure> _saveFailure(
    Object error, {
    String? id,
  }) async {
    final message = coachMemoryErrorMessage(error);
    if (id != null && isCoachMemoryGoneError(error)) {
      final reloaded = await load();
      return CoachMemorySaveFailure(
        '$message${reloaded ? ' Die Liste ist neu geladen.' : ''} '
        '„Sichern“ legt sie als neue Notiz an.',
        entryGone: true,
      );
    }
    if (isCoachMemoryConflictError(error)) {
      final reloaded = await load();
      return CoachMemorySaveFailure(
        reloaded
            ? '$message Die Liste ist neu geladen; sichere erneut, um deine '
                  'Fassung zu übernehmen.'
            : '$message Lade die Liste neu, bevor du erneut sicherst.',
      );
    }
    if (isCoachMemoryFullError(error)) await load();
    return CoachMemorySaveFailure(message);
  }

  /// Meldet einen Fehler auf dem Screen, etwa wenn das Notiz-Sheet schon zu
  /// war, als das Speichern scheiterte.
  void reportActionError(String message) {
    if (_disposed) return;
    actionError = message;
    _notify();
  }

  /// Ersetzt einen vorhandenen Eintrag an seiner Stelle (der Server sortiert
  /// nach Anlage) oder stellt einen neuen an den Anfang.
  void _put(ApiCoachMemory memory) {
    if (!items.any((item) => item.id == memory.id)) {
      items = [memory, ...items];
      return;
    }
    items = [
      for (final item in items)
        if (item.id == memory.id) memory else item,
    ];
  }

  /// Löscht auf dem Server; die Zeile entfernt danach [removeLocally], damit
  /// das Wischen zu Ende animieren kann.
  Future<bool> delete(String id) =>
      _change(() => repository.delete(id), onError: _reportError);

  void removeLocally(String id) {
    items = [
      for (final item in items)
        if (item.id != id) item,
    ];
    _notify();
  }

  Future<bool> deleteAll() => _change(() async {
    await repository.deleteAll();
    items = const [];
  }, onError: _reportError);

  void _reportError(Object error) =>
      actionError = coachMemoryErrorMessage(error);

  Future<bool> _change(
    Future<void> Function() action, {
    required void Function(Object error) onError,
  }) async {
    if (_disposed || !canEdit) return false;
    isBusy = true;
    actionError = null;
    _notify();
    try {
      await action();
      return !_disposed;
    } on Object catch (error) {
      if (_disposed) return false;
      isOffline = isCoachMemoryOfflineError(error);
      onError(error);
      return false;
    } finally {
      if (!_disposed) {
        isBusy = false;
        _notify();
      }
    }
  }

  static const _offlineReason =
      'Keine Verbindung. Dein Gedächtnis lässt sich nur online ansehen und '
      'ändern.';

  static const _busyReason =
      'Gerade läuft noch eine Änderung. Versuche es gleich erneut.';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
