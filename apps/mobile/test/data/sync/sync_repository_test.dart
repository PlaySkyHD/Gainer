import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';

const accountId = 'a1234567-1234-4234-8234-123456789abc';
const checkInId = 'b1234567-1234-4234-8234-123456789abc';
const mutationId = 'c1234567-1234-4234-8234-123456789abc';
const clientId = 'd1234567-1234-4234-8234-123456789abc';

void main() {
  late Directory directory;
  late HttpServer server;
  late List<HttpRequest> received;
  late bool activeWriter;
  late int registrationStatus;
  late bool failMutation;
  late String? mutationFailureCode;
  late int mutationFailureStatus;
  late int pullCursor;
  late int pullRevision;
  late String sessionUserId;
  late String antiforgeryUserId;
  late String pullResourceType;
  late int pullVersion;
  late int handoverBeginStatus;
  late List<Map<String, dynamic>> handoverBeginRequests;
  late List<Map<String, dynamic>> handoverCompleteRequests;
  late bool handoverCompleteActiveWriter;
  late int handoverCompleteRevision;
  _MemoryPendingHandoverSecretStore? activeHandoverSecretStore;
  Completer<void>? sessionGate;
  Completer<void>? sessionEntered;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gainer-sync-');
    received = [];
    activeWriter = true;
    registrationStatus = 200;
    failMutation = false;
    mutationFailureCode = null;
    mutationFailureStatus = 503;
    pullCursor = 0;
    pullRevision = 1;
    sessionUserId = accountId;
    antiforgeryUserId = accountId;
    pullResourceType = 'DailyCheckIn';
    pullVersion = 1;
    handoverBeginStatus = 200;
    handoverBeginRequests = [];
    handoverCompleteRequests = [];
    handoverCompleteActiveWriter = true;
    handoverCompleteRevision = 1;
    activeHandoverSecretStore = null;
    sessionGate = null;
    sessionEntered = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      received.add(request);
      final path = request.uri.path;
      if (path == '/api/v1/auth/session' && request.method == 'GET') {
        if (sessionGate != null) {
          sessionEntered?.complete();
          await sessionGate!.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'userId': sessionUserId,
            'email': 'fixture@example.test',
            'isAccountOperator': false,
          }),
        );
      } else if (path == '/api/v1/auth/antiforgery' &&
          request.method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'requestToken': 'csrf-fixture',
            'authenticatedUserId': antiforgeryUserId,
          }),
        );
      } else if (path.startsWith('/api/v1/sync/clients/') &&
          request.method == 'PUT') {
        await _readBody(request);
        request.response.statusCode = registrationStatus;
        request.response.headers.contentType = ContentType.json;
        if (registrationStatus == 200) {
          request.response.write(
            jsonEncode({
              'clientId': clientId,
              'displayName': 'Gainer iPhone',
              'protocolVersion': 2,
              'isActiveWriter': activeWriter,
              'registeredAtUtc': '2026-10-12T10:00:00Z',
              'lastSeenAtUtc': '2026-10-12T10:00:00Z',
            }),
          );
        } else {
          request.response.write(
            jsonEncode({
              'code': 'authentication_required',
              'message': 'Sign in required.',
            }),
          );
        }
      } else if (path.startsWith('/api/v1/sync/mutations/') &&
          request.method == 'PUT') {
        final body =
            jsonDecode(await _readBody(request)) as Map<String, dynamic>;
        if (failMutation || mutationFailureCode != null) {
          request.response.statusCode = mutationFailureStatus;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'code': mutationFailureCode ?? 'temporary_unavailable',
              'message': 'Retry later.',
            }),
          );
        } else {
          expect(body['protocolVersion'], 2);
          expect(body['clientSequence'], 1);
          expect(body['resources'].single['resourceType'], 'DailyCheckIn');
          expect(body['operation'], 'createDailyCheckIn');
          expect(body['clientId'], clientId);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'mutationId': mutationId,
              'replayed': false,
              'revision': 1,
              'resources': [],
            }),
          );
        }
      } else if (path == '/api/v1/sync/changes' && request.method == 'GET') {
        final after = int.parse(request.uri.queryParameters['after']!);
        request.response.headers.contentType = ContentType.json;
        if (!failMutation &&
            (mutationFailureCode == null ||
                mutationFailureCode == 'stale_version') &&
            after < 1 &&
            pullCursor == 0) {
          pullCursor = pullRevision;
          request.response.write(
            jsonEncode({
              'protocolVersion': 2,
              'nextCursor': pullRevision,
              'hasMore': false,
              'batches': [
                {
                  'batchId': 'e1234567-1234-4234-8234-123456789abc',
                  'revision': pullRevision,
                  'originMutationId':
                      activeWriter &&
                          mutationFailureCode == null &&
                          !failMutation
                      ? mutationId
                      : null,
                  'changes': [
                    {
                      'resourceType': pullResourceType,
                      'resourceId': checkInId,
                      'version': pullVersion,
                      'isTombstone': false,
                      'snapshot': {
                        'localDate': '2026-10-12',
                        'values': {'weightKg': 81.5},
                        'createdAtUtc': '2026-10-12T10:00:00Z',
                        'updatedAtUtc': '2026-10-12T10:00:00Z',
                      },
                    },
                  ],
                },
              ],
            }),
          );
        } else {
          request.response.write(
            jsonEncode({
              'protocolVersion': 2,
              'nextCursor': after,
              'hasMore': false,
              'batches': [],
            }),
          );
        }
      } else if (path == '/api/v1/sync/handovers' && request.method == 'POST') {
        final body =
            jsonDecode(await _readBody(request)) as Map<String, dynamic>;
        handoverBeginRequests.add(body);
        request.response.statusCode = handoverBeginStatus;
        request.response.headers.contentType = ContentType.json;
        if (handoverBeginStatus == 200) {
          request.response.write(
            jsonEncode({
              'handoverId': 'f1234567-1234-4234-8234-123456789abc',
              'oneTimeCode': 'once-only-fixture',
              'frozenRevision': body['expectedRevision'],
              'expiresAtUtc': '2026-10-13T10:00:00Z',
            }),
          );
        } else {
          request.response.write(
            jsonEncode({
              'code': 'handover_in_progress',
              'message': 'A handover is already in progress.',
            }),
          );
        }
      } else if (path.startsWith('/api/v1/sync/handovers/') &&
          path.endsWith('/complete') &&
          request.method == 'POST') {
        final body =
            jsonDecode(await _readBody(request)) as Map<String, dynamic>;
        handoverCompleteRequests.add(body);
        final pendingBytes = activeHandoverSecretStore?.value;
        expect(pendingBytes, isNotNull);
        final pending = PendingHandoverRecord.decode(pendingBytes!);
        expect(pending.phase, 'targetCompletePending');
        expect(pending.frozenRevision, handoverCompleteRevision);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'handoverId': 'f1234567-1234-4234-8234-123456789abc',
            'targetClientId': clientId,
            'frozenRevision': handoverCompleteRevision,
            'isActiveWriter': handoverCompleteActiveWriter,
            'completedAtUtc': '2026-10-12T10:00:00Z',
          }),
        );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<(LocalSyncStore, LocalDatabase, ApiClient, SyncRepository)> fixture({
    PendingHandoverSecretStore? handoverSecrets,
  }) async {
    if (handoverSecrets is _MemoryPendingHandoverSecretStore) {
      activeHandoverSecretStore = handoverSecrets;
    }
    final database = LocalDatabase(
      NativeDatabase(File('${directory.path}/account.sqlite')),
    );
    final store = LocalSyncStore(database: database, accountId: accountId);
    final identity = InstallationIdentityStore(database);
    // Use a controlled stable identity for contract assertions.
    await database
        .into(database.installationMetadata)
        .insertOnConflictUpdate(
          InstallationMetadataCompanion.insert(
            key: 'installation-id',
            value: clientId,
          ),
        );
    final api = ApiClient(
      configuration: ApiConfiguration(
        apiOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
        trustedFrontendOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
        allowInsecureLoopbackForDevelopment: true,
      ),
    );
    final repository = SyncRepository(
      store: store,
      api: api,
      installationIdentity: identity,
      displayName: 'Gainer iPhone',
      handoverSecrets: handoverSecrets,
    );
    return (store, database, api, repository);
  }

  test('active writer uses Sync v2 PascalCase resource, then atomically pulls its batch', () async {
    final (store, database, api, repository) = await fixture();
    await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'daily-check-in',
      aggregateId: checkInId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'localDate': '2026-10-12', 'weightKg': 81.5},
      envelope: localEnvelope(
        aggregateId: checkInId,
        workingCopy: {'localDate': '2026-10-12', 'weightKg': 81.5},
      ),
    );
    final queuedBeforeCrash = (await store.readOutbox()).single;
    await store.updateMutation(
      LocalMutation(
        mutationId: queuedBeforeCrash.mutationId,
        accountId: queuedBeforeCrash.accountId,
        aggregateType: queuedBeforeCrash.aggregateType,
        aggregateId: queuedBeforeCrash.aggregateId,
        sequence: queuedBeforeCrash.sequence,
        status: LocalMutationStatus.syncing,
        createdAtUtc: queuedBeforeCrash.createdAtUtc,
        operation: queuedBeforeCrash.operation,
        baseVersion: queuedBeforeCrash.baseVersion,
        body: queuedBeforeCrash.body,
        clientSequence: 1,
        dependsOnMutationId: queuedBeforeCrash.dependsOnMutationId,
      ),
    );

    final result = await repository.synchronize(
      now: DateTime.utc(2026, 10, 12),
    );
    expect(result.state, SyncRunState.synced);
    expect(result.pushed, 1);
    expect(result.pulledBatches, 1);
    expect(await store.readOutbox(), isEmpty);
    expect(await store.readSyncMetadata('pull-cursor'), 1);
    final saved = await store.readAggregate('daily-check-in', checkInId);
    expect(saved?.serverVersion, 1);
    expect(saved?.workingCopy, {
      'weightKg': 81.5,
      'localDate': '2026-10-12',
      'createdAtUtc': '2026-10-12T10:00:00Z',
      'updatedAtUtc': '2026-10-12T10:00:00Z',
    });

    final push = received.firstWhere(
      (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
    );
    expect(push.headers.value('Origin'), 'http://127.0.0.1:${server.port}');
    expect(push.headers.value('X-CSRF-TOKEN'), 'csrf-fixture');
    api.close();
    await database.close();
  });

  test('inactive registered client still performs read-only pull and does not push', () async {
    activeWriter = false;
    final (store, database, api, repository) = await fixture();
    await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'daily-check-in',
      aggregateId: checkInId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'localDate': '2026-10-12'},
      envelope: localEnvelope(
        aggregateId: checkInId,
        workingCopy: {'localDate': '2026-10-12'},
      ),
    );

    final result = await repository.synchronize();
    expect(result.state, SyncRunState.inactiveClient);
    expect(result.pushed, 0);
    expect(result.pulledBatches, 1);
    expect(
      (await store.readOutbox()).single.status,
      LocalMutationStatus.pending,
    );
    expect(
      received.any(
        (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
      ),
      isFalse,
    );
    api.close();
    await database.close();
  });

  test('401 pauses queue without deleting mutation', () async {
    registrationStatus = 401;
    final (store, database, api, repository) = await fixture();
    await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'daily-check-in',
      aggregateId: checkInId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'localDate': '2026-10-12'},
      envelope: localEnvelope(
        aggregateId: checkInId,
        workingCopy: {'localDate': '2026-10-12'},
      ),
    );
    final result = await repository.synchronize();
    expect(result.state, SyncRunState.authBlocked);
    expect(
      (await store.readOutbox()).single.status,
      LocalMutationStatus.authBlocked,
    );
    api.close();
    await database.close();
  });

  test(
    'a different authenticated account cannot register or push this outbox',
    () async {
      sessionUserId = 'f1234567-1234-4234-8234-123456789abc';
      final (store, database, api, repository) = await fixture();
      await store.commitMutation(
        mutationId: mutationId,
        aggregateType: 'daily-check-in',
        aggregateId: checkInId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: {'localDate': '2026-10-12'},
        envelope: localEnvelope(
          aggregateId: checkInId,
          workingCopy: {'localDate': '2026-10-12'},
        ),
      );
      await expectLater(repository.synchronize(), throwsStateError);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.pending,
      );
      expect(
        received.any(
          (request) => request.uri.path.startsWith('/api/v1/sync/clients/'),
        ),
        isFalse,
      );
      expect(
        received.any(
          (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
        ),
        isFalse,
      );
      api.close();
      await database.close();
    },
  );

  test(
    'antiforgery identity mismatch blocks sync before client registration',
    () async {
      antiforgeryUserId = 'f1234567-1234-4234-8234-123456789abc';
      final (store, database, api, repository) = await fixture();
      await expectLater(
        repository.synchronize(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'account_changed',
          ),
        ),
      );
      expect(
        received.any(
          (request) => request.uri.path.startsWith('/api/v1/sync/clients/'),
        ),
        isFalse,
      );
      api.close();
      await database.close();
    },
  );

  test(
    'concurrent mutation 409 remains retryable rather than a user conflict',
    () async {
      mutationFailureCode = 'concurrent_mutation';
      mutationFailureStatus = 409;
      final (store, database, api, repository) = await fixture();
      await store.commitMutation(
        mutationId: mutationId,
        aggregateType: 'daily-check-in',
        aggregateId: checkInId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: {'localDate': '2026-10-12', 'weightKg': 81.5},
        envelope: localEnvelope(
          aggregateId: checkInId,
          workingCopy: {'localDate': '2026-10-12', 'weightKg': 81.5},
        ),
      );

      await repository.synchronize(now: DateTime.utc(2026, 10, 12));
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.pending,
      );
      expect(await database.select(database.localConflicts).get(), isEmpty);

      mutationFailureCode = null;
      await repository.synchronize(now: DateTime.utc(2026, 10, 12, 0, 1));
      expect(await store.readOutbox(), isEmpty);
      api.close();
      await database.close();
    },
  );

  test(
    'unknown sync resource rejects its batch and leaves cursor unchanged',
    () async {
      pullResourceType = 'FutureCatalogItem';
      final (store, database, api, repository) = await fixture();
      await expectLater(repository.synchronize(), throwsFormatException);
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      api.close();
      await database.close();
    },
  );

  test(
    'a version conflict keeps a server snapshot and retry uses a new ID/base',
    () async {
      mutationFailureCode = 'stale_version';
      mutationFailureStatus = 409;
      pullVersion = 4;
      final (store, database, api, repository) = await fixture();
      await store.commitMutation(
        mutationId: mutationId,
        aggregateType: 'daily-check-in',
        aggregateId: checkInId,
        operation: LocalMutationOperation.update,
        baseVersion: 2,
        body: {'localDate': '2026-10-12', 'weightKg': 82.5},
        envelope: LocalAggregateEnvelope(
          aggregateId: checkInId,
          serverSnapshot: {'weightKg': 80.0},
          workingCopy: {'weightKg': 82.5},
          serverVersion: 2,
          optimisticVersion: 3,
          syncState: LocalSyncState.pending,
        ),
      );
      await repository.synchronize();
      final conflict =
          (await database.select(database.localConflicts).get()).single;
      expect(conflict.code, 'stale_version');
      final before = (await store.readOutbox()).single;
      expect(before.status, LocalMutationStatus.conflict);
      expect(
        (await store.readAggregate('daily-check-in', checkInId))?.serverVersion,
        4,
      );

      final replacementId = 'f1234567-1234-4234-8234-123456789abc';
      await store.retryConflictOnCurrentServerVersion(
        conflictId: conflict.conflictId,
        replacementMutationId: replacementId,
        createdAtUtc: DateTime.utc(2026, 10, 12, 0, 1),
      );
      final replacement = (await store.readOutbox()).single;
      expect(replacement.mutationId, replacementId);
      expect(replacement.baseVersion, 4);
      expect(replacement.clientSequence, isNull);
      expect(replacement.dependsOnMutationId, mutationId);
      api.close();
      await database.close();
    },
  );

  test('second repository instance observes the durable sync lease', () async {
    final (store, database, api, repository) = await fixture();
    sessionGate = Completer<void>();
    sessionEntered = Completer<void>();
    final firstRun = repository.synchronize();
    await sessionEntered!.future;
    final secondRepository = SyncRepository(
      store: store,
      api: api,
      installationIdentity: InstallationIdentityStore(database),
      displayName: 'Gainer iPhone',
    );
    final second = await secondRepository.synchronize();
    expect(second.state, SyncRunState.busy);
    sessionGate!.complete();
    expect((await firstRun).state, SyncRunState.synced);
    expect(
      received.where((request) => request.uri.path == '/api/v1/auth/session'),
      hasLength(1),
    );
    api.close();
    await database.close();
  });

  test(
    'begin handover persists request identity first and keeps conflict frozen',
    () async {
      handoverBeginStatus = 409;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      const firstRequestId = 'a2234567-1234-4234-8234-123456789abc';
      await expectLater(
        repository.beginHandover(requestId: firstRequestId),
        throwsA(isA<ApiException>()),
      );
      final pendingBytes = await secretStore.read(
        apiOrigin: api.configuration.canonicalApiOrigin,
        accountId: accountId,
      );
      final pending = PendingHandoverRecord.decode(pendingBytes!);
      expect(pending.requestId, firstRequestId);
      expect(pending.phase, 'sourceBeginPending');
      expect(pending.handoverId, isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);

      handoverBeginStatus = 200;
      final response = await repository.beginHandover(
        requestId: 'b2234567-1234-4234-8234-123456789abc',
      );
      expect(response.handoverId, 'f1234567-1234-4234-8234-123456789abc');
      expect(handoverBeginRequests, hasLength(2));
      expect(handoverBeginRequests.map((body) => body['requestId']), [
        firstRequestId,
        firstRequestId,
      ]);
      final completedRecord = PendingHandoverRecord.decode(
        (await secretStore.read(
          apiOrigin: api.configuration.canonicalApiOrigin,
          accountId: accountId,
        ))!,
      );
      expect(completedRecord.phase, 'sourceBegan');
      expect(completedRecord.oneTimeCode, 'once-only-fixture');
      api.close();
      await database.close();
    },
  );

  test('complete persists the secret before requests and sends only the frozen revision', () async {
    pullRevision = 7;
    handoverCompleteRevision = 1;
    final secretStore = _MemoryPendingHandoverSecretStore();
    final (store, database, api, repository) = await fixture(
      handoverSecrets: secretStore,
    );
    final response = await repository.completeHandover(
      handoverId: 'f1234567-1234-4234-8234-123456789abc',
      oneTimeCode: 'target-one-time-code',
      frozenRevision: 1,
      sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
      expiresAtUtc: DateTime.utc(2026, 10, 13),
    );
    expect(response.isActiveWriter, isTrue);
    expect(handoverCompleteRequests.single['caughtUpRevision'], 1);
    expect(
      handoverCompleteRequests.single['oneTimeCode'],
      'target-one-time-code',
    );
    expect(await store.readSyncMetadata('pull-cursor'), 7);
    expect(await store.readSyncMetadata('local-writes-frozen'), isFalse);
    expect(secretStore.value, isNull);
    api.close();
    await database.close();
  });

  test(
    'unconfirmed active writer response retains the secure record and freeze',
    () async {
      handoverCompleteActiveWriter = false;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      await expectLater(
        repository.completeHandover(
          handoverId: 'f1234567-1234-4234-8234-123456789abc',
          oneTimeCode: 'target-one-time-code',
          frozenRevision: 1,
          sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
          expiresAtUtc: DateTime.utc(2026, 10, 13),
        ),
        throwsStateError,
      );
      final retained = PendingHandoverRecord.decode(secretStore.value!);
      expect(retained.phase, 'targetCompletePending');
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
      api.close();
      await database.close();
    },
  );
}

Future<String> _readBody(HttpRequest request) async =>
    await utf8.decoder.bind(request).join();

class _MemoryPendingHandoverSecretStore implements PendingHandoverSecretStore {
  Uint8List? value;

  @override
  Future<void> write({
    required String apiOrigin,
    required String accountId,
    required Uint8List record,
  }) async {
    value = Uint8List.fromList(record);
  }

  @override
  Future<Uint8List?> read({
    required String apiOrigin,
    required String accountId,
  }) async => value == null ? null : Uint8List.fromList(value!);

  @override
  Future<void> clear({
    required String apiOrigin,
    required String accountId,
  }) async {
    value = null;
  }
}
