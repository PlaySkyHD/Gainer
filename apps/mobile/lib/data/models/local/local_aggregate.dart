import 'dart:convert';

enum LocalSyncState { clean, pending, conflict, authBlocked, failed }

/// The server copy is never mutated by an offline edit. [workingCopy] is the
/// user's current view; [serverVersion] remains null until the server assigns it.
class LocalAggregateEnvelope<T> {
  LocalAggregateEnvelope({
    required this.aggregateId,
    required T? serverSnapshot,
    required T workingCopy,
    required int? serverVersion,
    required this.optimisticVersion,
    required this.syncState,
  }) : serverSnapshot = serverSnapshot == null
           ? null
           : immutableJsonValue(serverSnapshot) as T,
       workingCopy = immutableJsonValue(workingCopy) as T,
       serverVersion = serverVersion {
    if (aggregateId.isEmpty) {
      throw ArgumentError.value(aggregateId, 'aggregateId');
    }
    if (serverVersion != null && serverVersion < 0) {
      throw ArgumentError.value(serverVersion, 'serverVersion');
    }
    if (optimisticVersion < 0) {
      throw ArgumentError.value(optimisticVersion, 'optimisticVersion');
    }
  }

  final String aggregateId;
  final T? serverSnapshot;
  final T workingCopy;
  final int? serverVersion;
  final int optimisticVersion;
  final LocalSyncState syncState;

  factory LocalAggregateEnvelope.fromJson(Map<String, dynamic> json) {
    final state = LocalSyncState.values.firstWhere(
      (value) => value.name == json['syncState'],
      orElse: () => throw const FormatException('Unknown local sync state.'),
    );
    return LocalAggregateEnvelope<T>(
      aggregateId: _requiredString(json, 'aggregateId'),
      serverSnapshot: json['serverSnapshot'] as T?,
      workingCopy: json['workingCopy'] as T,
      serverVersion: json['serverVersion'] as int?,
      optimisticVersion: json['optimisticVersion'] as int,
      syncState: state,
    );
  }

  Map<String, Object?> toJson() => {
    'aggregateId': aggregateId,
    'serverSnapshot': serverSnapshot,
    'workingCopy': workingCopy,
    'serverVersion': serverVersion,
    'optimisticVersion': optimisticVersion,
    'syncState': syncState.name,
  };

  String encode() => jsonEncode(toJson());
}

LocalAggregateEnvelope<Object?> serverEnvelope({
  required String aggregateId,
  required Object? snapshot,
  required int version,
}) {
  if (version < 0) throw ArgumentError.value(version, 'version');
  return LocalAggregateEnvelope(
    aggregateId: aggregateId,
    serverSnapshot: snapshot,
    workingCopy: snapshot,
    serverVersion: version,
    optimisticVersion: version,
    syncState: LocalSyncState.clean,
  );
}

LocalAggregateEnvelope<Object?> localEnvelope({
  required String aggregateId,
  required Object? workingCopy,
}) => LocalAggregateEnvelope(
  aggregateId: aggregateId,
  serverSnapshot: null,
  workingCopy: workingCopy,
  serverVersion: null,
  optimisticVersion: 1,
  syncState: LocalSyncState.pending,
);

/// Clones JSON-compatible values and recursively freezes maps and lists so UI
/// references cannot mutate a saved working copy or its server base.
Object? immutableJsonValue(Object? value) =>
    _freezeJson(jsonDecode(jsonEncode(value)));

Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeJson(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  return value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Invalid $key.');
  return value;
}
