class SyncResourceVersionRequest {
  const SyncResourceVersionRequest({
    required this.resourceType,
    required this.resourceId,
    required this.baseVersion,
  });

  final String resourceType;
  final String resourceId;
  final int baseVersion;

  Map<String, Object?> toJson() => {
    'resourceType': resourceType,
    'resourceId': resourceId,
    'baseVersion': baseVersion,
  };
}

class SyncMutationRequest {
  const SyncMutationRequest({
    required this.protocolVersion,
    required this.clientId,
    required this.clientSequence,
    required this.operation,
    required this.resources,
    required this.payload,
    this.dependsOnMutationId,
  });

  final int protocolVersion;
  final String clientId;
  final int clientSequence;
  final String operation;
  final List<SyncResourceVersionRequest> resources;
  final String? dependsOnMutationId;
  final Object? payload;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'clientId': clientId,
    'clientSequence': clientSequence,
    'operation': operation,
    'resources': resources.map((resource) => resource.toJson()).toList(),
    'dependsOnMutationId': dependsOnMutationId,
    'payload': payload,
  };
}

class SyncClientRegistrationRequest {
  const SyncClientRegistrationRequest({
    required this.clientId,
    required this.displayName,
    required this.protocolVersion,
    required this.takeOverWriting,
  });

  final String clientId;
  final String displayName;
  final int protocolVersion;
  final bool takeOverWriting;

  Map<String, Object?> toJson() => {
    'clientId': clientId,
    'displayName': displayName,
    'protocolVersion': protocolVersion,
    'takeOverWriting': takeOverWriting,
  };
}

class SyncClientRegistrationResponse {
  const SyncClientRegistrationResponse({
    required this.clientId,
    required this.displayName,
    required this.protocolVersion,
    required this.isActiveWriter,
    required this.registeredAtUtc,
    required this.lastSeenAtUtc,
  });

  final String clientId;
  final String displayName;
  final int protocolVersion;
  final bool isActiveWriter;
  final DateTime registeredAtUtc;
  final DateTime lastSeenAtUtc;

  factory SyncClientRegistrationResponse.fromJson(Map<String, dynamic> json) =>
      SyncClientRegistrationResponse(
        clientId: _string(json, 'clientId'),
        displayName: _string(json, 'displayName'),
        protocolVersion: _int(json, 'protocolVersion'),
        isActiveWriter: _bool(json, 'isActiveWriter'),
        registeredAtUtc: _utc(json, 'registeredAtUtc'),
        lastSeenAtUtc: _utc(json, 'lastSeenAtUtc'),
      );
}

class SyncMutationResponse {
  const SyncMutationResponse({
    required this.mutationId,
    required this.replayed,
    required this.revision,
    required this.resources,
  });

  final String mutationId;
  final bool replayed;
  final int revision;
  final List<SyncResourceResult> resources;

  factory SyncMutationResponse.fromJson(Map<String, dynamic> json) =>
      SyncMutationResponse(
        mutationId: _string(json, 'mutationId'),
        replayed: _bool(json, 'replayed'),
        revision: _int(json, 'revision'),
        resources: _objectList(
          json,
          'resources',
        ).map(SyncResourceResult.fromJson).toList(growable: false),
      );
}

class SyncResourceResult {
  const SyncResourceResult({
    required this.resourceType,
    required this.resourceId,
    required this.version,
    required this.isTombstone,
    this.snapshot,
  });

  final String resourceType;
  final String resourceId;
  final int version;
  final Object? snapshot;
  final bool isTombstone;

  factory SyncResourceResult.fromJson(Map<String, dynamic> json) =>
      SyncResourceResult(
        resourceType: _string(json, 'resourceType'),
        resourceId: _string(json, 'resourceId'),
        version: _int(json, 'version'),
        snapshot: json['snapshot'],
        isTombstone: _bool(json, 'isTombstone'),
      );
}

class SyncPullResponse {
  const SyncPullResponse({
    required this.protocolVersion,
    required this.nextCursor,
    required this.hasMore,
    required this.batches,
  });

  final int protocolVersion;
  final int nextCursor;
  final bool hasMore;
  final List<SyncChangeBatchResponse> batches;

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) =>
      SyncPullResponse(
        protocolVersion: _int(json, 'protocolVersion'),
        nextCursor: _int(json, 'nextCursor'),
        hasMore: _bool(json, 'hasMore'),
        batches: _objectList(
          json,
          'batches',
        ).map(SyncChangeBatchResponse.fromJson).toList(growable: false),
      );
}

class SyncChangeBatchResponse {
  const SyncChangeBatchResponse({
    required this.batchId,
    required this.revision,
    required this.changes,
    this.originMutationId,
  });

  final String batchId;
  final int revision;
  final String? originMutationId;
  final List<SyncChangeResponse> changes;

  factory SyncChangeBatchResponse.fromJson(Map<String, dynamic> json) =>
      SyncChangeBatchResponse(
        batchId: _string(json, 'batchId'),
        revision: _int(json, 'revision'),
        originMutationId: json['originMutationId'] as String?,
        changes: _objectList(
          json,
          'changes',
        ).map(SyncChangeResponse.fromJson).toList(growable: false),
      );
}

class SyncChangeResponse {
  const SyncChangeResponse({
    required this.resourceType,
    required this.resourceId,
    required this.version,
    required this.isTombstone,
    this.snapshot,
  });

  final String resourceType;
  final String resourceId;
  final int version;
  final bool isTombstone;
  final Object? snapshot;

  factory SyncChangeResponse.fromJson(Map<String, dynamic> json) =>
      SyncChangeResponse(
        resourceType: _string(json, 'resourceType'),
        resourceId: _string(json, 'resourceId'),
        version: _int(json, 'version'),
        isTombstone: _bool(json, 'isTombstone'),
        snapshot: json['snapshot'],
      );
}

/// Planned additive handover contract from the active migration design.
/// These DTOs are not currently served by the backend OpenAPI document.
class BeginSyncHandoverRequest {
  const BeginSyncHandoverRequest({
    required this.requestId,
    required this.sourceClientId,
    required this.expectedRevision,
  });

  final String requestId;
  final String sourceClientId;
  final int expectedRevision;

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'sourceClientId': sourceClientId,
    'expectedRevision': expectedRevision,
  };
}

class BeginSyncHandoverResponse {
  const BeginSyncHandoverResponse({
    required this.handoverId,
    required this.oneTimeCode,
    required this.frozenRevision,
    required this.expiresAtUtc,
  });

  final String handoverId;
  final String oneTimeCode;
  final int frozenRevision;
  final DateTime expiresAtUtc;

  factory BeginSyncHandoverResponse.fromJson(Map<String, dynamic> json) =>
      BeginSyncHandoverResponse(
        handoverId: _string(json, 'handoverId'),
        oneTimeCode: _string(json, 'oneTimeCode'),
        frozenRevision: _int(json, 'frozenRevision'),
        expiresAtUtc: _utc(json, 'expiresAtUtc'),
      );
}

class CompleteSyncHandoverRequest {
  const CompleteSyncHandoverRequest({
    required this.oneTimeCode,
    required this.targetClientId,
    required this.caughtUpRevision,
  });

  final String oneTimeCode;
  final String targetClientId;
  final int caughtUpRevision;

  Map<String, Object?> toJson() => {
    'oneTimeCode': oneTimeCode,
    'targetClientId': targetClientId,
    'caughtUpRevision': caughtUpRevision,
  };
}

class CompleteSyncHandoverResponse {
  const CompleteSyncHandoverResponse({
    required this.handoverId,
    required this.targetClientId,
    required this.frozenRevision,
    required this.isActiveWriter,
    required this.completedAtUtc,
  });

  final String handoverId;
  final String targetClientId;
  final int frozenRevision;
  final bool isActiveWriter;
  final DateTime completedAtUtc;

  factory CompleteSyncHandoverResponse.fromJson(Map<String, dynamic> json) =>
      CompleteSyncHandoverResponse(
        handoverId: _string(json, 'handoverId'),
        targetClientId: _string(json, 'targetClientId'),
        frozenRevision: _int(json, 'frozenRevision'),
        isActiveWriter: _bool(json, 'isActiveWriter'),
        completedAtUtc: _utc(json, 'completedAtUtc'),
      );
}

class CancelSyncHandoverRequest {
  const CancelSyncHandoverRequest({required this.sourceClientId});

  final String sourceClientId;

  Map<String, Object?> toJson() => {'sourceClientId': sourceClientId};
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Invalid $key.');
  return value;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Invalid $key.');
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid $key.');
  return value;
}

DateTime _utc(Map<String, dynamic> json, String key) =>
    DateTime.parse(_string(json, key)).toUtc();

List<Map<String, dynamic>> _objectList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((entry) => entry is! Map<String, dynamic>)) {
    throw FormatException('Invalid $key.');
  }
  return value.cast<Map<String, dynamic>>();
}
