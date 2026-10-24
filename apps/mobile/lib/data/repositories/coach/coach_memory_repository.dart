import '../../models/api/coach_memory_api_models.dart';
import '../../services/api/api_client.dart';

/// Coach-Gedächtnis des Kontos. Nur online: Der Coach selbst ist online-only,
/// deshalb gibt es keinen Sync-Ressourcentyp und keine Outbox.
abstract interface class CoachMemoryRepository {
  Future<ApiCoachMemoryList> list();

  /// Legt eine Notiz an; ein bereits gemerkter Text liefert den bestehenden
  /// Eintrag, sodass „Merken“ doppelt getippt werden darf.
  Future<ApiCoachMemory> create(CoachMemoryCategory category, String text);

  Future<ApiCoachMemory> update(
    String id,
    CoachMemoryCategory category,
    String text,
  );

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
    String text,
  ) => api.updateCoachMemory(id, category, text);

  @override
  Future<void> delete(String id) => api.deleteCoachMemory(id);

  @override
  Future<void> deleteAll() => api.deleteAllCoachMemories();
}

/// Verständlicher Text zu einem Fehler beim Ändern des Gedächtnisses.
String coachMemoryErrorMessage(Object error) => switch (error) {
  ApiException(code: 'memory_limit_reached') =>
    'Das Gedächtnis ist voll. Lösche zuerst eine Notiz.',
  ApiException(code: 'memory_duplicate') => 'Diese Notiz gibt es schon.',
  ApiException(code: 'memory_not_found') =>
    'Die Notiz gibt es nicht mehr. Lade die Liste neu.',
  ApiException(code: 'network_error') =>
    'Keine Verbindung. Das Gedächtnis lässt sich nur online ändern.',
  _ => 'Das hat nicht geklappt. Versuche es erneut.',
};

/// True, wenn der Fehler an fehlender Verbindung liegt.
bool isCoachMemoryOfflineError(Object error) =>
    error is ApiException && error.code == 'network_error';
