import '../../../domain/models/timer/rest_timer_shortcuts.dart';
import '../../../domain/models/timer/rest_timer_state.dart';
import '../../services/local/local_database.dart';
import '../sync/local_sync_store.dart';

const _timerKeyPrefix = 'trainingTimer:';
const _shortcutsKey = 'trainingTimerShortcuts';

/// Device-local rest timer state and shortcuts. Stored as account-bound
/// metadata of [LocalSyncStore]; it never creates outbox mutations or touches
/// workout versions.
class RestTimerStore {
  RestTimerStore({required this.store});

  final LocalSyncStore store;

  /// Returns the stored timer, or a ready timer with the default duration if
  /// nothing is stored. A running timer whose target time has passed is
  /// returned as expired. The conversion is not persisted.
  Future<RestTimerState> load(String workoutId, {required DateTime now}) async {
    final key = _timerKey(workoutId);
    final raw = await store.readSyncMetadata(key);
    final state = raw == null
        ? RestTimerState.ready(workoutId: workoutId)
        : _decodeTimer(raw, workoutId);
    return state.expire(now: now);
  }

  /// Persists [state] unless a state with the same or a newer generation is
  /// already stored. Returns false for a discarded (stale) write.
  Future<bool> save(RestTimerState state) async {
    final key = _timerKey(state.workoutId);
    return store.database.transaction(() async {
      final raw = await store.readSyncMetadata(key);
      if (raw != null &&
          state.generation <= _decodeTimer(raw, state.workoutId).generation) {
        return false;
      }
      await store.writeSyncMetadata(key, state.toJson());
      return true;
    });
  }

  Future<RestTimerShortcuts> loadShortcuts() async {
    final raw = await store.readSyncMetadata(_shortcutsKey);
    if (raw == null) return RestTimerShortcuts.defaults;
    if (raw is! List || raw.any((value) => value is! int)) {
      throw const FormatException('Invalid rest timer shortcuts.');
    }
    return RestTimerShortcuts.fromSeconds(raw.cast<int>());
  }

  Future<void> saveShortcuts(RestTimerShortcuts shortcuts) {
    return store.writeSyncMetadata(_shortcutsKey, shortcuts.seconds);
  }

  String _timerKey(String workoutId) {
    if (!RegExp(LocalDatabase.accountIdPattern).hasMatch(workoutId)) {
      throw ArgumentError.value(workoutId, 'workoutId', 'Expected a UUID.');
    }
    return '$_timerKeyPrefix$workoutId';
  }

  RestTimerState _decodeTimer(Object? raw, String workoutId) {
    if (raw is! Map<String, dynamic> || raw['workoutId'] != workoutId) {
      throw const FormatException('Invalid rest timer state.');
    }
    return RestTimerState.fromJson(raw);
  }
}
