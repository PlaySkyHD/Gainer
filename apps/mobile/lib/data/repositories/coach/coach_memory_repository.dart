import '../../models/api/coach_memory_api_models.dart';
import '../../services/api/api_client.dart';

/// Coach-Gedächtnis des Kontos. Nur online: Der Coach selbst ist online-only,
/// deshalb gibt es keinen Sync-Ressourcentyp und keine Outbox.
abstract interface class CoachMemoryRepository {
  Future<ApiCoachMemoryList> list();

  /// Legt eine Notiz an; ein bereits gemerkter Text liefert den bestehenden
  /// Eintrag mit der neuen Kategorie, sodass „Merken“ doppelt getippt werden
  /// darf.
  Future<ApiCoachMemory> create(CoachMemoryCategory category, String text);

  /// Ändert eine Notiz, die zuletzt in [baseVersion] gelesen wurde. Ist sie
  /// inzwischen anders, scheitert das mit `memory_conflict`. Ein
  /// [unknownCategory] geht statt [category] unverändert zurück.
  Future<ApiCoachMemory> update(
    String id,
    CoachMemoryCategory category,
    String text, {
    int? baseVersion,
    String? unknownCategory,
  });

  /// Löscht eine Notiz. Gibt es sie schon nicht mehr, gilt das als Erfolg.
  Future<void> delete(String id);

  Future<void> deleteAll();
}

class ApiCoachMemoryRepository implements CoachMemoryRepository {
  const ApiCoachMemoryRepository(this.api);

  final ApiClient api;

  @override
  Future<ApiCoachMemoryList> list() => api.listCoachMemories();

  @override
  Future<ApiCoachMemory> create(CoachMemoryCategory category, String text) =>
      api.createCoachMemory(category, text);

  @override
  Future<ApiCoachMemory> update(
    String id,
    CoachMemoryCategory category,
    String text, {
    int? baseVersion,
    String? unknownCategory,
  }) => api.updateCoachMemory(
    id,
    category,
    text,
    baseVersion: baseVersion,
    unknownCategory: unknownCategory,
  );

  @override
  Future<void> delete(String id) async {
    try {
      await api.deleteCoachMemory(id);
    } on ApiException catch (error) {
      // Schon gelöscht, etwa auf einem anderen Gerät: Ziel erreicht.
      if (error.statusCode != 404) rethrow;
    }
  }

  @override
  Future<void> deleteAll() => api.deleteAllCoachMemories();
}

/// Verständlicher Text zu einem Fehler beim Ändern des Gedächtnisses.
String coachMemoryErrorMessage(Object error) => switch (error) {
  ApiException(code: 'memory_limit_reached') =>
    'Das Gedächtnis ist voll. Lösche zuerst eine Notiz.',
  ApiException(code: 'memory_duplicate') => 'Diese Notiz gibt es schon.',
  ApiException(code: 'memory_not_found') => 'Die Notiz gibt es nicht mehr.',
  ApiException(code: 'memory_conflict') =>
    'Die Notiz wurde inzwischen auf einem anderen Gerät geändert.',
  ApiException(code: 'network_error') =>
    'Keine Verbindung. Das Gedächtnis lässt sich nur online ändern.',
  _ => 'Das hat nicht geklappt. Versuche es erneut.',
};

/// True, wenn der Fehler an fehlender Verbindung liegt.
bool isCoachMemoryOfflineError(Object error) =>
    error is ApiException && error.code == 'network_error';

/// True, wenn der Server das Gedächtnis als voll meldet.
bool isCoachMemoryFullError(Object error) =>
    error is ApiException && error.code == 'memory_limit_reached';

/// True, wenn die Notiz inzwischen anderswo geändert wurde.
bool isCoachMemoryConflictError(Object error) =>
    error is ApiException && error.code == 'memory_conflict';

/// True, wenn es die Notiz auf dem Server nicht mehr gibt.
bool isCoachMemoryGoneError(Object error) =>
    error is ApiException && error.code == 'memory_not_found';
