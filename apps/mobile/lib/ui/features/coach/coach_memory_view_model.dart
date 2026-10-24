import 'package:flutter/foundation.dart';

import '../../../data/models/api/coach_memory_api_models.dart';
import '../../../data/repositories/coach/coach_memory_repository.dart';

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

  Future<void> load() async {
    if (_disposed || isLoading) return;
    isLoading = true;
    loadError = null;
    actionError = null;
    _notify();
    try {
      final result = await repository.list();
      if (_disposed) return;
      items = result.items;
      maxEntries = result.maxEntries;
      isLoaded = true;
      isOffline = false;
    } on Object catch (error) {
      if (_disposed) return;
      isOffline = isCoachMemoryOfflineError(error);
      loadError = isOffline
          ? _offlineReason
          : 'Das Gedächtnis konnte nicht geladen werden. Versuche es erneut.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Legt eine Notiz an ([id] null) oder ändert sie. True bei Erfolg.
  Future<bool> save({
    String? id,
    required CoachMemoryCategory category,
    required String text,
  }) => _change(() async {
    if (id == null) {
      final created = await repository.create(category, text);
      items = [created, ...items.where((item) => item.id != created.id)];
    } else {
      final updated = await repository.update(id, category, text);
      items = [for (final item in items) item.id == id ? updated : item];
    }
  });

  /// Löscht auf dem Server; die Zeile entfernt danach [removeLocally], damit
  /// das Wischen zu Ende animieren kann.
  Future<bool> delete(String id) => _change(() => repository.delete(id));

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
  });

  Future<bool> _change(Future<void> Function() action) async {
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
      actionError = coachMemoryErrorMessage(error);
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
