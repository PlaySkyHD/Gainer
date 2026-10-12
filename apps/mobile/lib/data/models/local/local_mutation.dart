import 'dart:convert';

import 'local_aggregate.dart';

enum LocalMutationStatus {
  pending,
  syncing,
  clean,
  authBlocked,
  inactiveClient,
  upgradeRequired,
  conflict,
  failed,
}

enum LocalMutationOperation { create, update, delete, complete, discard }

class LocalMutation {
  LocalMutation({
    required this.mutationId,
    required this.accountId,
    required this.aggregateType,
    required this.aggregateId,
    required this.sequence,
    required this.status,
    required this.createdAtUtc,
    required this.operation,
    required this.baseVersion,
    required Object? body,
    this.clientSequence,
    this.dependsOnMutationId,
    this.attemptCount = 0,
    this.nextAttemptAtUtc,
    this.lastErrorCode,
  }) : body = immutableJsonValue(body);

  final String mutationId;
  final String accountId;
  final String aggregateType;
  final String aggregateId;
  final int sequence;
  final LocalMutationStatus status;
  final DateTime createdAtUtc;
  final LocalMutationOperation operation;
  final int? baseVersion;
  final Object? body;
  final int? clientSequence;
  final String? dependsOnMutationId;
  final int attemptCount;
  final DateTime? nextAttemptAtUtc;
  final String? lastErrorCode;

  String get aggregateKey => '$aggregateType:$aggregateId';

  Map<String, Object?> immutablePayload() => {
    'operation': operation.name,
    'baseVersion': baseVersion,
    'body': body,
  };

  String encodePayload() => jsonEncode(immutablePayload());
}

class LocalConflictRecord {
  LocalConflictRecord({
    required this.conflictId,
    required this.aggregateType,
    required this.aggregateId,
    required this.createdAtUtc,
    required this.code,
    required Object? detail,
  }) : detail = immutableJsonValue(detail);

  final String conflictId;
  final String aggregateType;
  final String aggregateId;
  final DateTime createdAtUtc;
  final String code;
  final Object? detail;
}

class LocalTombstoneRecord {
  const LocalTombstoneRecord({
    required this.resourceType,
    required this.resourceId,
    required this.revision,
  });

  final String resourceType;
  final String resourceId;
  final int revision;
}
