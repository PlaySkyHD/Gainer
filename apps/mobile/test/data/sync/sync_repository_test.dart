import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_conflict_recovery.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/auth/sync_foreground_scheduler.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/data/services/local/pending_handover_secret_store.dart';

const accountId = 'a1234567-1234-4234-8234-123456789abc';
const checkInId = 'b1234567-1234-4234-8234-123456789abc';
const mutationId = 'c1234567-1234-4234-8234-123456789abc';
const clientId = 'd1234567-1234-4234-8234-123456789abc';

/// Mutation eines anderen Geräts; liegt nie in der lokalen Outbox.
const foreignMutationId = 'e9234567-1234-4234-8234-123456789abc';

void main() {
  late Directory directory;
  late HttpServer server;
  late List<HttpRequest> received;
  late bool activeWriter;
  late int registrationStatus;
  late bool failMutation;
  late String? mutationFailureCode;
  late int mutationFailureStatus;
  Map<String, Object?>? mutationFailureErrors;
  late String? pullFailureCode;
  late int pullFailureStatus;
  late bool switchAccountAfterRegistration;
  late int pullCursor;
  late int pullRevision;
  late String sessionUserId;
  late String serverAccountId;
  late String pullResourceType;
  String? pullResourceId;
  Map<String, Object?>? pullSnapshot;
  bool pullTombstone = false;
  late int pullVersion;
  late int handoverBeginStatus;
  late List<Map<String, dynamic>> handoverBeginRequests;
  late List<Map<String, dynamic>> handoverCompleteRequests;
  late bool handoverCompleteActiveWriter;
  late int handoverCompleteRevision;
  late int handoverCompleteStatus;
  late String handoverCompleteFailureCode;
  late int handoverCompleteSideEffects;
  late bool serverHandoverAlreadyCompleted;
  late List<Map<String, dynamic>> registrationRequests;
  late Set<String> acceptedMutationIds;
  late bool lenientMutations;
  late List<Map<String, dynamic>> receivedMutations;
  late Completer<void>? acceptedMutation;
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
    mutationFailureErrors = null;
    pullFailureCode = null;
    pullFailureStatus = 409;
    switchAccountAfterRegistration = false;
    pullCursor = 0;
    pullRevision = 1;
    sessionUserId = accountId;
    serverAccountId = accountId;
    pullResourceType = 'DailyCheckIn';
    pullResourceId = null;
    pullSnapshot = null;
    pullTombstone = false;
    pullVersion = 1;
    handoverBeginStatus = 200;
    handoverBeginRequests = [];
    handoverCompleteRequests = [];
    handoverCompleteActiveWriter = true;
    handoverCompleteRevision = 1;
    handoverCompleteStatus = 200;
    handoverCompleteFailureCode = 'handover_expired';
    handoverCompleteSideEffects = 0;
    serverHandoverAlreadyCompleted = false;
    registrationRequests = [];
    acceptedMutationIds = <String>{};
    lenientMutations = false;
    receivedMutations = [];
    acceptedMutation = null;
    activeHandoverSecretStore = null;
    sessionGate = null;
    sessionEntered = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      received.add(request);
      final path = request.uri.path;
      // Mirrors the API's account guard on scoped sync requests.
      final expectedAccount = request.headers.value('x-gainer-account-id');
      if (expectedAccount != null && expectedAccount != serverAccountId) {
        request.response.statusCode = 409;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'code': 'account_changed',
            'title':
                'The authenticated account does not match this sync profile.',
          }),
        );
        await request.response.close();
        return;
      }
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
      } else if (path.startsWith('/api/v1/sync/clients/') &&
          request.method == 'PUT') {
        registrationRequests.add(
          jsonDecode(await _readBody(request)) as Map<String, dynamic>,
        );
        request.response.statusCode = registrationStatus;
        request.response.headers.contentType = ContentType.json;
        if (registrationStatus == 200) {
          request.response.write(
            jsonEncode({
              'clientId': clientId,
              'displayName': 'Gainer iPhone',
              'protocolVersion': 4,
              'isActiveWriter': activeWriter,
              'registeredAtUtc': '2026-10-12T10:00:00Z',
              'lastSeenAtUtc': '2026-10-12T10:00:00Z',
            }),
          );
          if (switchAccountAfterRegistration) {
            serverAccountId = 'f1234567-1234-4234-8234-123456789abc';
            switchAccountAfterRegistration = false;
          }
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
              'errors': ?mutationFailureErrors,
            }),
          );
        } else {
          receivedMutations.add(body);
          expect(body['protocolVersion'], 4);
          expect(body['clientId'], clientId);
          if (!lenientMutations) {
            expect(body['clientSequence'], 1);
            expect(body['resources'].single['resourceType'], 'DailyCheckIn');
            expect(body['operation'], 'createDailyCheckIn');
          }
          acceptedMutationIds.add(path.split('/').last);
          acceptedMutation?.complete();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'mutationId': lenientMutations
                  ? path.split('/').last
                  : mutationId,
              'replayed': false,
              'revision': 1,
              'resources': [],
            }),
          );
        }
      } else if (path == '/api/v1/sync/changes' && request.method == 'GET') {
        final after = int.parse(request.uri.queryParameters['after']!);
        // Die App nennt ihre Protokollversion; der Server antwortet in ihr.
        final protocol = int.parse(
          request.uri.queryParameters['protocolVersion']!,
        );
        request.response.headers.contentType = ContentType.json;
        if (pullFailureCode != null) {
          request.response.statusCode = pullFailureStatus;
          request.response.write(
            jsonEncode({
              'code': pullFailureCode,
              'message': 'Account identity changed.',
            }),
          );
        } else if (!failMutation &&
            (mutationFailureCode == null ||
                mutationFailureCode == 'stale_version') &&
            after < 1 &&
            pullCursor == 0) {
          pullCursor = pullRevision;
          request.response.write(
            jsonEncode({
              'protocolVersion': protocol,
              'nextCursor': pullRevision,
              'hasMore': false,
              'batches': [
                {
                  'batchId': 'e1234567-1234-4234-8234-123456789abc',
                  'revision': pullRevision,
                  // Der Server setzt die Herkunft bei jedem Batch, auch
                  // bei denen anderer Geräte.
                  'originMutationId':
                      activeWriter &&
                          mutationFailureCode == null &&
                          !failMutation
                      ? mutationId
                      : foreignMutationId,
                  'changes': [
                    {
                      'resourceType': pullResourceType,
                      'resourceId': pullResourceId ?? checkInId,
                      'version': pullVersion,
                      'isTombstone': pullTombstone,
                      'snapshot': pullTombstone
                          ? null
                          : pullSnapshot ??
                                {
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
              'protocolVersion': protocol,
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
        request.response.statusCode = handoverCompleteStatus;
        if (handoverCompleteStatus == 200) {
          if (!serverHandoverAlreadyCompleted) {
            handoverCompleteSideEffects++;
            serverHandoverAlreadyCompleted = true;
          }
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
          request.response.write(
            jsonEncode({
              'code': handoverCompleteFailureCode,
              'message': 'Handover is no longer pending.',
            }),
          );
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
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
    expect(push.headers.value('Origin'), isNull);
    expect(push.headers.value('X-CSRF-TOKEN'), isNull);
    expect(push.headers.value('X-Gainer-Account-Id'), accountId);
    api.close();
    await database.close();
  });

  test('inactive registered client still performs read-only pull and does not push', () async {
    activeWriter = false;
    // Ein anderes Gerät ändert einen anderen Eintrag; dieselbe Ressource wäre
    // ein Konflikt (siehe „a foreign batch keeps the pending base …“).
    pullResourceId = 'b9234567-1234-4234-8234-123456789abc';
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
    'a different authenticated account pauses this outbox before registration',
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
      final report = await repository.synchronize();
      expect(report.state, SyncRunState.authBlocked);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.authBlocked,
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
    'server account guard pauses the outbox at client registration',
    () async {
      serverAccountId = 'f1234567-1234-4234-8234-123456789abc';
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
      final report = await repository.synchronize();
      expect(report.state, SyncRunState.authBlocked);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.authBlocked,
      );
      expect(registrationRequests, isEmpty);
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

  test('account_changed during push preserves the outbox without creating a conflict', () async {
    switchAccountAfterRegistration = true;
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

    final report = await repository.synchronize();
    expect(report.state, SyncRunState.authBlocked);
    expect(
      (await store.readOutbox()).single.status,
      LocalMutationStatus.authBlocked,
    );
    // The server's account guard rejects the push before applying it.
    expect(receivedMutations, isEmpty);
    api.close();
    await database.close();
  });

  test(
    'account_changed during pull pauses the outbox and keeps the cursor',
    () async {
      activeWriter = false;
      pullFailureCode = 'account_changed';
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

      final report = await repository.synchronize();
      expect(report.state, SyncRunState.authBlocked);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.authBlocked,
      );
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      api.close();
      await database.close();
    },
  );

  test(
    'upgrade_required during pull asks for an update and keeps the cursor',
    () async {
      activeWriter = false;
      pullFailureCode = 'upgrade_required';
      final (store, database, api, repository) = await fixture();

      final report = await repository.synchronize();

      expect(report.state, SyncRunState.upgradeRequired);
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      api.close();
      await database.close();
    },
  );

  test('entries an older app parked with upgrade_required are sent after the update', () async {
    final (store, database, api, repository) = await fixture();
    final parked = await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'daily-check-in',
      aggregateId: checkInId,
      operation: LocalMutationOperation.create,
      baseVersion: null,
      body: {'localDate': '2026-10-12', 'weightKg': 82.5},
      envelope: localEnvelope(
        aggregateId: checkInId,
        workingCopy: {'localDate': '2026-10-12', 'weightKg': 82.5},
      ),
    );
    await store.updateMutation(
      LocalMutation(
        mutationId: parked.mutationId,
        accountId: parked.accountId,
        aggregateType: parked.aggregateType,
        aggregateId: parked.aggregateId,
        sequence: parked.sequence,
        status: LocalMutationStatus.upgradeRequired,
        createdAtUtc: parked.createdAtUtc,
        operation: parked.operation,
        baseVersion: parked.baseVersion,
        body: parked.body,
        lastErrorCode: 'upgrade_required',
      ),
    );

    final report = await repository.synchronize();

    expect(report.pushed, 1);
    expect(receivedMutations.single['operation'], 'createDailyCheckIn');
    api.close();
    await database.close();
  });

  test(
    'a push rejected with upgrade_required is not resent by the same version',
    () async {
      mutationFailureCode = 'upgrade_required';
      mutationFailureStatus = 409;
      final (store, database, api, repository) = await fixture();
      await store.commitMutation(
        mutationId: mutationId,
        aggregateType: 'daily-check-in',
        aggregateId: checkInId,
        operation: LocalMutationOperation.create,
        baseVersion: null,
        body: {'localDate': '2026-10-12', 'weightKg': 82.5},
        envelope: localEnvelope(
          aggregateId: checkInId,
          workingCopy: {'localDate': '2026-10-12', 'weightKg': 82.5},
        ),
      );

      final first = await repository.synchronize();
      expect(first.state, SyncRunState.upgradeRequired);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.upgradeRequired,
      );

      // Derselbe App-Stand sendet den Eintrag nicht in einer Schleife neu.
      int mutationRequests() => received
          .where((r) => r.uri.path.startsWith('/api/v1/sync/mutations/'))
          .length;
      final sentBefore = mutationRequests();
      expect(sentBefore, 1);
      await repository.synchronize();
      expect(mutationRequests(), sentBefore);
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.upgradeRequired,
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
    'transient push retry resumes on its deadline and drains the same mutation',
    () async {
      mutationFailureCode = 'temporary_unavailable';
      mutationFailureStatus = 503;
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
      var now = DateTime.utc(2026, 10, 12, 10);
      final timers = <_SyncTimerStub>[];
      final scheduler = SyncForegroundScheduler(
        observeLifecycle: false,
        isActive: () => true,
        clock: () => now,
        timerFactory: (duration, callback) {
          final timer = _SyncTimerStub(duration, callback);
          timers.add(timer);
          return timer;
        },
        synchronize: () => repository.synchronize(now: now),
        retryDelays: const [Duration(seconds: 4)],
      );

      await scheduler.start();
      expect(scheduler.lastReport?.state, SyncRunState.retryPending);
      final retryAt = scheduler.lastReport!.nextRetryAtUtc!;
      expect(retryAt, now.add(const Duration(seconds: 1)));
      expect(timers.single.duration, const Duration(seconds: 1));
      expect(
        (await store.readOutbox()).single.status,
        LocalMutationStatus.pending,
      );
      expect(acceptedMutationIds, isEmpty);
      expect(
        received.where(
          (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
        ),
        hasLength(1),
      );

      mutationFailureCode = null;
      acceptedMutation = Completer<void>();
      now = retryAt;
      timers.single.fire();
      await acceptedMutation!.future.timeout(const Duration(seconds: 5));
      for (
        var attempt = 0;
        attempt < 50 && scheduler.lastReport?.state != SyncRunState.synced;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(scheduler.lastReport?.state, SyncRunState.synced);
      expect(await store.readOutbox(), isEmpty);
      expect(acceptedMutationIds, {mutationId});
      expect(
        received.where(
          (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
        ),
        hasLength(2),
      );
      await scheduler.dispose();
      api.close();
      await database.close();
    },
  );

  Future<void> pullTrainingSnapshot({
    required String resourceType,
    required String resourceId,
    required String aggregateType,
    required Map<String, Object?> snapshot,
  }) async {
    pullResourceType = resourceType;
    pullResourceId = resourceId;
    pullSnapshot = snapshot;
    final (store, database, api, repository) = await fixture();
    await repository.synchronize();
    final saved = await store.readAggregate(aggregateType, resourceId);
    expect(saved?.aggregateId, resourceId);
    expect(saved?.serverVersion, 1);
    expect(saved?.serverSnapshot, isNotNull);
    expect(saved?.syncState, LocalSyncState.clean);
    expect(await store.readSyncMetadata('pull-cursor'), 1);
    api.close();
    await database.close();
  }

  const workoutId = '44444444-4444-4444-8444-444444444444';
  final workoutSnapshot = <String, Object?>{
    'workoutId': workoutId,
    'title': 'Push',
    'notes': null,
    'startedAtUtc': '2026-10-17T08:00:00Z',
    'endedAtUtc': '2026-10-17T09:00:00Z',
    'previousValueSource': 'exercise',
    'sourcePlanId': null,
    'sourceWorkoutId': null,
    'exercises': [
      {
        'workoutExerciseId': '55555555-5555-4555-8555-555555555555',
        'sourceExerciseId': '66666666-6666-4666-8666-666666666666',
        'exerciseNameSnapshot': 'Bankdrücken',
        'exerciseTypeSnapshot': 'strength',
        'notes': null,
        'supersetId': null,
        'sets': [
          {
            'setId': '77777777-7777-4777-8777-777777777777',
            'setType': 'future-type',
            'weightKg': 80,
            'repetitions': 5,
            'rir': null,
            'notes': null,
          },
        ],
      },
    ],
    'createdAtUtc': '2026-10-17T08:00:00Z',
    'updatedAtUtc': '2026-10-17T09:00:00Z',
  };

  test(
    'pulls a workout snapshot and reads unknown set types as normal',
    () async {
      await pullTrainingSnapshot(
        resourceType: 'Workout',
        resourceId: workoutId,
        aggregateType: 'workout',
        snapshot: workoutSnapshot,
      );
    },
  );

  test('pulls a training plan snapshot', () async {
    await pullTrainingSnapshot(
      resourceType: 'TrainingPlan',
      resourceId: '88888888-8888-4888-8888-888888888888',
      aggregateType: 'training-plan',
      snapshot: {
        'planId': '88888888-8888-4888-8888-888888888888',
        'name': 'Push A',
        'notes': null,
        'previousValueSource': 'plan',
        'entries': <Object?>[],
        'sortOrder': 0,
        'isArchived': true,
        'createdAtUtc': '2026-10-17T08:00:00Z',
        'updatedAtUtc': '2026-10-17T08:00:00Z',
      },
    );
  });

  test('pulls a training schedule snapshot', () async {
    await pullTrainingSnapshot(
      resourceType: 'TrainingSchedule',
      resourceId: '99999999-9999-4999-8999-999999999999',
      aggregateType: 'training-schedule',
      snapshot: {
        'scheduleId': '99999999-9999-4999-8999-999999999999',
        'mode': 'weekly',
        'anchorDate': null,
        'validFrom': '2026-10-17',
        'slots': [
          for (var i = 0; i < 7; i++) {'planId': null},
        ],
        'shifts': <Object?>[],
        'exceptions': <Object?>[],
        'updatedAtUtc': '2026-10-17T08:00:00Z',
      },
    );
  });

  test('pulls a custom exercise snapshot', () async {
    await pullTrainingSnapshot(
      resourceType: 'CustomExercise',
      resourceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      aggregateType: 'custom-exercise',
      snapshot: {
        'exerciseId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'values': {'name': 'Rudern', 'exerciseType': 'strength'},
        'isArchived': false,
        'createdAtUtc': '2026-10-17T08:00:00Z',
        'updatedAtUtc': '2026-10-17T08:00:00Z',
      },
    );
  });

  test('pulls an exercise category snapshot', () async {
    await pullTrainingSnapshot(
      resourceType: 'ExerciseCategory',
      resourceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      aggregateType: 'exercise-category',
      snapshot: {
        'categoryId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'name': 'Beine',
        'isArchived': false,
        'createdAtUtc': '2026-10-17T08:00:00Z',
        'updatedAtUtc': '2026-10-17T08:00:00Z',
      },
    );
  });

  test(
    'a deleted workout pulls as a tombstone and removes the local copy',
    () async {
      pullResourceType = 'Workout';
      pullResourceId = workoutId;
      pullTombstone = true;
      final (store, database, api, repository) = await fixture();
      await repository.synchronize();
      expect(await store.readAggregate('workout', workoutId), isNull);
      expect(await store.hasTombstone('Workout', workoutId), isTrue);
      expect(await store.readSyncMetadata('pull-cursor'), 1);
      api.close();
      await database.close();
    },
  );

  group('training schedule tombstones', () {
    const scheduleId = '77777777-7777-4777-8777-777777777777';
    Map<String, Object?> scheduleBody({String? deletedAtUtc}) => {
      'scheduleId': scheduleId,
      'mode': 'cycle',
      'anchorDate': '2026-10-12',
      'validFrom': '2026-10-12',
      'slots': [
        {'planId': null},
      ],
      'shifts': <Object?>[],
      'exceptions': <Object?>[],
      'deletedAtUtc': ?deletedAtUtc,
    };

    test('a pulled schedule tombstone keeps a deletion marker with its '
        'version', () async {
      pullResourceType = 'TrainingSchedule';
      pullResourceId = scheduleId;
      pullTombstone = true;
      pullVersion = 6;
      final (store, database, api, repository) = await fixture();
      await repository.synchronize();

      final marker = await store.readAggregate('training-schedule', scheduleId);
      expect(marker, isNotNull);
      expect(marker!.serverVersion, 6);
      expect(marker.syncState, LocalSyncState.clean);
      expect((marker.workingCopy! as Map)['deletedAtUtc'], isNotNull);
      api.close();
      await database.close();
    });

    test('own confirmed delete followed by a new save is no conflict and '
        'moves the save onto the tombstone version', () async {
      pullResourceType = 'TrainingSchedule';
      pullResourceId = scheduleId;
      pullTombstone = true;
      pullVersion = 4;
      final (store, database, api, repository) = await fixture();
      final deletedBody = scheduleBody(deletedAtUtc: '2026-10-12T10:00:00Z');
      await store.commitMutation(
        mutationId: mutationId,
        aggregateType: 'training-schedule',
        aggregateId: scheduleId,
        operation: LocalMutationOperation.delete,
        baseVersion: 3,
        body: deletedBody,
        envelope: LocalAggregateEnvelope<Object?>(
          aggregateId: scheduleId,
          serverSnapshot: scheduleBody(),
          workingCopy: deletedBody,
          serverVersion: 3,
          optimisticVersion: 4,
          syncState: LocalSyncState.pending,
        ),
      );
      // Der Server hat die Löschung bestätigt; ihr Batch kommt erst beim Pull.
      await (database.update(
        database.localOutbox,
      )..where((t) => t.mutationId.equals(mutationId))).write(
        LocalOutboxCompanion(
          status: const Value('clean'),
          sentAtUtc: Value(DateTime.utc(2026, 10, 12).toIso8601String()),
        ),
      );
      await store.commitMutation(
        mutationId: 'e7777777-7777-4777-8777-777777777777',
        aggregateType: 'training-schedule',
        aggregateId: scheduleId,
        operation: LocalMutationOperation.update,
        baseVersion: 3,
        body: scheduleBody(),
        envelope: LocalAggregateEnvelope<Object?>(
          aggregateId: scheduleId,
          serverSnapshot: scheduleBody(),
          workingCopy: scheduleBody(),
          serverVersion: 3,
          optimisticVersion: 5,
          syncState: LocalSyncState.pending,
        ),
      );
      lenientMutations = true;

      await repository.synchronize();

      expect(await database.select(database.localConflicts).get(), isEmpty);
      final save = (await store.readOutbox(aggregateType: 'training-schedule'))
          .single;
      expect(save.mutationId, 'e7777777-7777-4777-8777-777777777777');
      final envelope = await store.readAggregate(
        'training-schedule',
        scheduleId,
      );
      expect(envelope!.workingCopy, scheduleBody());
      expect(save.status, LocalMutationStatus.pending);
      expect(save.baseVersion, 4);
      expect(envelope.serverVersion, 4);
      expect(envelope.syncState, LocalSyncState.pending);
      api.close();
      await database.close();
    });
  });

  test('an archived plan arrives as a snapshot, not as a tombstone', () async {
    await pullTrainingSnapshot(
      resourceType: 'TrainingPlan',
      resourceId: '88888888-8888-4888-8888-888888888888',
      aggregateType: 'training-plan',
      snapshot: {
        'planId': '88888888-8888-4888-8888-888888888888',
        'name': 'Alt',
        'notes': null,
        'previousValueSource': 'exercise',
        'entries': <Object?>[],
        'sortOrder': 1,
        'isArchived': true,
        'createdAtUtc': '2026-10-17T08:00:00Z',
        'updatedAtUtc': '2026-10-17T08:00:00Z',
      },
    );
  });

  test('a custom exercise with an unknown exercise type rejects the batch and asks for an update', () async {
    pullResourceType = 'CustomExercise';
    pullResourceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    pullSnapshot = {
      'exerciseId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'values': {'name': 'Neu', 'exerciseType': 'unknown'},
      'isArchived': false,
      'createdAtUtc': '2026-10-17T08:00:00Z',
      'updatedAtUtc': '2026-10-17T08:00:00Z',
    };
    final (store, database, api, repository) = await fixture();

    final report = await repository.synchronize();

    expect(report.state, SyncRunState.upgradeRequired);
    expect(report.pulledBatches, 0);
    expect(await store.readSyncMetadata('pull-cursor'), isNull);
    expect(
      await store.readAggregate(
        'custom-exercise',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      isNull,
    );
    api.close();
    await database.close();
  });

  const workoutAggregateId = '44444444-4444-4444-8444-444444444445';
  final workoutWorkingCopy = <String, Object?>{
    'workoutId': workoutAggregateId,
    'title': 'Push',
    'notes': null,
    'startedAtUtc': '2026-10-17T08:00:00Z',
    'endedAtUtc': '2026-10-17T07:00:00Z',
    'previousValueSource': 'exercise',
    'sourcePlanId': null,
    'sourceWorkoutId': null,
    'exercises': <Object?>[],
    'deletedAtUtc': null,
  };

  Future<void> commitWorkoutUpdate(LocalSyncStore store) async {
    await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'workout',
      aggregateId: workoutAggregateId,
      operation: LocalMutationOperation.update,
      baseVersion: 1,
      body: workoutWorkingCopy,
      envelope: LocalAggregateEnvelope<Object?>(
        aggregateId: workoutAggregateId,
        serverSnapshot: {...workoutWorkingCopy, 'endedAtUtc': null},
        workingCopy: workoutWorkingCopy,
        serverVersion: 1,
        optimisticVersion: 2,
        syncState: LocalSyncState.pending,
      ),
    );
  }

  int workoutPushCount() => received
      .where(
        (request) =>
            request.method == 'PUT' &&
            request.uri.path.startsWith('/api/v1/sync/mutations/'),
      )
      .length;

  test('409 active_workout_exists keeps a visible, non-retried conflict and does not resend', () async {
    mutationFailureCode = 'active_workout_exists';
    mutationFailureStatus = 409;
    final (store, database, api, repository) = await fixture();
    await commitWorkoutUpdate(store);

    await repository.synchronize();
    await repository.synchronize();

    expect(workoutPushCount(), 1);
    final conflict =
        (await database.select(database.localConflicts).get()).single;
    expect(conflict.code, 'active_workout_exists');
    expect(conflict.aggregateType, 'workout');
    expect(conflict.aggregateId, workoutAggregateId);
    final outbox = (await store.readOutbox()).single;
    expect(outbox.status, LocalMutationStatus.conflict);
    expect(outbox.lastErrorCode, 'active_workout_exists');
    final local = await store.readAggregate('workout', workoutAggregateId);
    expect(local?.workingCopy, workoutWorkingCopy);
    await expectLater(
      store.retryConflictOnCurrentServerVersion(
        conflictId: conflict.conflictId,
        replacementMutationId: 'e1234567-1234-4234-8234-123456789abc',
        createdAtUtc: DateTime.utc(2026, 10, 17),
      ),
      throwsStateError,
    );
    api.close();
    await database.close();
  });

  test('forcing a rejected workout create sends the ended workout and clears the conflict', () async {
    mutationFailureCode = 'active_workout_exists';
    mutationFailureStatus = 409;
    final (store, database, api, repository) = await fixture();
    final active = {...workoutWorkingCopy, 'endedAtUtc': null};
    await store.commitMutation(
      mutationId: mutationId,
      aggregateType: 'workout',
      aggregateId: workoutAggregateId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: active,
      envelope: localEnvelope(
        aggregateId: workoutAggregateId,
        workingCopy: active,
      ),
      createdAtUtc: DateTime.utc(2026, 10, 17, 8),
    );
    await repository.synchronize();
    final conflict =
        (await database.select(database.localConflicts).get()).single;
    expect(conflict.code, 'active_workout_exists');

    // Das Training wurde inzwischen beendet; der Nutzer erzwingt den Stand.
    final ended = {...workoutWorkingCopy, 'endedAtUtc': '2026-10-17T09:00:00Z'};
    await store.commitMutation(
      mutationId: 'e1234567-1234-4234-8234-123456789abc',
      aggregateType: 'workout',
      aggregateId: workoutAggregateId,
      operation: LocalMutationOperation.update,
      baseVersion: null,
      body: ended,
      envelope: LocalAggregateEnvelope<Object?>(
        aggregateId: workoutAggregateId,
        serverSnapshot: null,
        workingCopy: ended,
        serverVersion: null,
        optimisticVersion: 2,
        syncState: LocalSyncState.pending,
      ),
    );
    await store.forceLocalState(
      conflictId: conflict.conflictId,
      replacementMutationId: 'f1234567-1234-4234-8234-123456789abc',
      createdAtUtc: DateTime.utc(2026, 10, 18),
    );
    mutationFailureCode = null;
    lenientMutations = true;
    receivedMutations.clear();

    final report = await repository.synchronize();

    expect(report.state, SyncRunState.synced);
    expect(receivedMutations, hasLength(1));
    final sent = receivedMutations.single;
    expect(sent['operation'], 'createWorkout');
    expect(sent['resources'].single['resourceType'], 'Workout');
    expect(sent['resources'].single['baseVersion'], 0);
    expect(sent['payload']['workout']['endedAtUtc'], '2026-10-17T09:00:00Z');
    expect(await database.select(database.localConflicts).get(), isEmpty);
    expect(
      (await store.readOutbox()).where(
        (m) => m.status == LocalMutationStatus.conflict,
      ),
      isEmpty,
    );
    api.close();
    await database.close();
  });

  test('422 validation_failed stores the field errors as a conflict and does not resend', () async {
    mutationFailureCode = 'validation_failed';
    mutationFailureStatus = 422;
    mutationFailureErrors = {
      'EndedAtUtc': ['The end time must be after the start time.'],
    };
    final (store, database, api, repository) = await fixture();
    await commitWorkoutUpdate(store);

    await repository.synchronize();
    await repository.synchronize();

    expect(workoutPushCount(), 1);
    final conflict =
        (await database.select(database.localConflicts).get()).single;
    expect(conflict.code, 'validation_failed');
    expect(conflict.aggregateId, workoutAggregateId);
    final detail = jsonDecode(conflict.detailJson) as Map<String, dynamic>;
    expect(detail['errors'], {
      'EndedAtUtc': ['The end time must be after the start time.'],
    });
    final outbox = (await store.readOutbox()).single;
    expect(outbox.status, LocalMutationStatus.conflict);
    expect(outbox.lastErrorCode, 'validation_failed');
    final local = await store.readAggregate('workout', workoutAggregateId);
    expect(local?.workingCopy, workoutWorkingCopy);
    await expectLater(
      store.retryConflictOnCurrentServerVersion(
        conflictId: conflict.conflictId,
        replacementMutationId: 'e1234567-1234-4234-8234-123456789abc',
        createdAtUtc: DateTime.utc(2026, 10, 17),
      ),
      throwsStateError,
    );
    api.close();
    await database.close();
  });

  test(
    'unknown sync resource asks for an update and leaves cursor unchanged',
    () async {
      pullResourceType = 'FutureCatalogItem';
      final (store, database, api, repository) = await fixture();
      final report = await repository.synchronize();
      expect(report.state, SyncRunState.upgradeRequired);
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      expect(
        await store.readAggregate('daily-check-in', checkInId),
        isNull,
        reason: 'Der Batch wird nicht teilweise angewendet.',
      );
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
      // Die abgelehnte Mutation landet nie in den verarbeiteten Mutationen
      // des Servers; eine Abhängigkeit darauf scheiterte immer.
      expect(replacement.dependsOnMutationId, isNull);

      mutationFailureCode = null;
      lenientMutations = true;
      await repository.synchronize();

      final sent = receivedMutations.single;
      expect(sent['dependsOnMutationId'], isNull);
      expect(sent['resources'].single['baseVersion'], 4);
      expect(await database.select(database.localConflicts).get(), isEmpty);
      api.close();
      await database.close();
    },
  );

  test(
    'a foreign batch keeps the pending base and records a visible conflict',
    () async {
      // Dieses Gerät schreibt nicht und ändert offline auf Basis v2; ein
      // anderes Gerät speichert v3.
      activeWriter = false;
      pullVersion = 3;
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

      final report = await repository.synchronize();

      expect(report.state, SyncRunState.inactiveClient);
      final waiting = (await store.readOutbox()).single;
      expect(waiting.baseVersion, 2);
      expect(waiting.status, LocalMutationStatus.conflict);
      final conflict =
          (await database.select(database.localConflicts).get()).single;
      expect(conflict.code, 'stale_base_version');
      expect(conflict.conflictId, mutationId);
      expect(jsonDecode(conflict.detailJson), {
        'mutationId': mutationId,
        'baseVersion': 2,
        'knownServerVersion': 3,
        'foreignChange': true,
      });
      final local = await store.readAggregate('daily-check-in', checkInId);
      expect(local?.workingCopy, {'weightKg': 82.5});
      expect(local?.serverVersion, 3);
      expect(local?.syncState, LocalSyncState.conflict);

      // Auch nach dem Übernehmen geht die Änderung nicht still auf v3 hinaus.
      activeWriter = true;
      await repository.synchronize(takeOverWriting: true);
      expect(receivedMutations, isEmpty);
      final infos = await store.readConflictResourceInfos();
      expect(infos[conflict.conflictId]?.hasServerState, isTrue);
      expect(infos[conflict.conflictId]?.canForceLocal, isTrue);
      api.close();
      await database.close();
    },
  );

  test('422 without validation_failed becomes a conflict that can only be discarded', () async {
    mutationFailureCode = 'invalid_payload';
    mutationFailureStatus = 422;
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

    await repository.synchronize();
    await repository.synchronize();

    expect(
      received.where(
        (request) => request.uri.path.startsWith('/api/v1/sync/mutations/'),
      ),
      hasLength(1),
    );
    final conflict =
        (await database.select(database.localConflicts).get()).single;
    expect(conflict.code, 'invalid_payload');
    expect(conflict.aggregateId, checkInId);
    expect(jsonDecode(conflict.detailJson)['permanent'], isTrue);
    final waiting = (await store.readOutbox()).single;
    expect(waiting.status, LocalMutationStatus.conflict);
    expect(waiting.lastErrorCode, 'invalid_payload');

    // Dieselben Daten scheitern erneut: weder erzwingen noch erneut senden.
    // Der Server kennt den Eintrag nicht, „Serverstand nutzen“ verwirft ihn.
    final info = (await store
        .readConflictResourceInfos())[conflict.conflictId]!;
    expect(info.canForceLocal, isFalse);
    expect(info.canRetry, isFalse);
    expect(info.hasServerState, isTrue);
    await expectLater(
      store.retryConflictOnCurrentServerVersion(
        conflictId: conflict.conflictId,
        replacementMutationId: 'f1234567-1234-4234-8234-123456789abc',
        createdAtUtc: DateTime.utc(2026, 10, 12),
      ),
      throwsStateError,
    );

    await store.acceptConflictServerState(conflict.conflictId);

    expect(await store.readOutbox(), isEmpty);
    expect(await database.select(database.localConflicts).get(), isEmpty);
    expect(await store.readAggregate('daily-check-in', checkInId), isNull);
    api.close();
    await database.close();
  });

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

  test(
    'sync and device handover register with the same current protocol',
    () async {
      pullRevision = 7;
      handoverCompleteRevision = 1;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (_, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );

      await repository.synchronize();
      await repository.completeHandover(
        handoverId: 'f1234567-1234-4234-8234-123456789abc',
        oneTimeCode: 'target-one-time-code',
        frozenRevision: 1,
        sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      );

      // Eine ältere Version bei der Übergabe setzte das Gerät beim Server
      // zurück und scheiterte nach dem ersten Wasser an `upgrade_required`.
      expect(registrationRequests.length, greaterThanOrEqualTo(2));
      expect(
        registrationRequests.map((body) => body['protocolVersion']),
        everyElement(nativeSyncProtocolVersion),
      );
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
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 10)),
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
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 10)),
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

  test(
    'expired fresh handover is rejected before freeze or any HTTP request',
    () async {
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      final requestsBefore = received.length;
      await expectLater(
        repository.completeHandover(
          handoverId: 'f1234567-1234-4234-8234-123456789abc',
          oneTimeCode: 'target-one-time-code',
          frozenRevision: 1,
          sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
          expiresAtUtc: DateTime.now().toUtc().subtract(
            const Duration(minutes: 1),
          ),
        ),
        throwsStateError,
      );
      expect(received.length, requestsBefore);
      expect(secretStore.value, isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isNull);
      api.close();
      await database.close();
    },
  );

  test('expired durable target completion replays and releases only on active confirmation', () async {
    pullRevision = 7;
    handoverCompleteRevision = 7;
    serverHandoverAlreadyCompleted = true;
    handoverCompleteSideEffects = 1;
    final secretStore = _MemoryPendingHandoverSecretStore();
    final (store, database, api, repository) = await fixture(
      handoverSecrets: secretStore,
    );
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    secretStore.value = PendingHandoverRecord(
      apiOrigin: api.configuration.canonicalApiOrigin,
      accountId: accountId,
      requestId: 'f1234567-1234-4234-8234-123456789abc',
      sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
      targetClientId: clientId,
      handoverId: 'f1234567-1234-4234-8234-123456789abc',
      phase: 'targetCompletePending',
      frozenRevision: 7,
      expiresAtUtc: expiry,
      oneTimeCode: 'target-one-time-code',
    ).encode();
    await store.freezeWritesIfOutboxEmpty();

    final becameWriter = await repository.recoverExpiredTargetHandover();

    expect(becameWriter, isTrue);
    expect(handoverCompleteRequests, hasLength(1));
    expect(handoverCompleteSideEffects, 1);
    expect(
      handoverCompleteRequests.single['oneTimeCode'],
      'target-one-time-code',
    );
    expect(handoverCompleteRequests.single['caughtUpRevision'], 7);
    final receivedPaths = received.map((request) => request.uri.path).toList();
    final pullIndex = receivedPaths.indexOf('/api/v1/sync/changes');
    final completeIndex = receivedPaths.indexOf(
      '/api/v1/sync/handovers/f1234567-1234-4234-8234-123456789abc/complete',
    );
    expect(pullIndex, greaterThanOrEqualTo(0));
    expect(completeIndex, greaterThan(pullIndex));
    expect(await store.readSyncMetadata('pull-cursor'), 7);
    expect(await store.readSyncMetadata('local-writes-frozen'), isFalse);
    expect(secretStore.value, isNull);
    api.close();
    await database.close();
  });

  test(
    'expired replay with inactive confirmation stays frozen and pending',
    () async {
      handoverCompleteActiveWriter = false;
      activeWriter = false;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      final expiry = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      secretStore.value = PendingHandoverRecord(
        apiOrigin: api.configuration.canonicalApiOrigin,
        accountId: accountId,
        requestId: 'f1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
        targetClientId: clientId,
        handoverId: 'f1234567-1234-4234-8234-123456789abc',
        phase: 'targetCompletePending',
        frozenRevision: 1,
        expiresAtUtc: expiry,
        oneTimeCode: 'target-one-time-code',
      ).encode();
      await store.freezeWritesIfOutboxEmpty();

      await expectLater(
        repository.completeHandover(
          handoverId: 'f1234567-1234-4234-8234-123456789abc',
          oneTimeCode: 'target-one-time-code',
          frozenRevision: 1,
          sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
          expiresAtUtc: expiry,
        ),
        throwsStateError,
      );
      expect(handoverCompleteRequests, hasLength(1));
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
      expect(
        PendingHandoverRecord.decode(secretStore.value!).phase,
        'targetCompletePending',
      );
      api.close();
      await database.close();
    },
  );

  test('definitive 409 expiry clears only after non-takeover registration, and inactive target stays frozen', () async {
    handoverCompleteStatus = 409;
    activeWriter = false;
    final secretStore = _MemoryPendingHandoverSecretStore();
    final (store, database, api, repository) = await fixture(
      handoverSecrets: secretStore,
    );
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    secretStore.value = PendingHandoverRecord(
      apiOrigin: api.configuration.canonicalApiOrigin,
      accountId: accountId,
      requestId: 'f1234567-1234-4234-8234-123456789abc',
      sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
      targetClientId: clientId,
      handoverId: 'f1234567-1234-4234-8234-123456789abc',
      phase: 'targetCompletePending',
      frozenRevision: 1,
      expiresAtUtc: expiry,
      oneTimeCode: 'target-one-time-code',
    ).encode();
    await store.freezeWritesIfOutboxEmpty();

    final becameWriter = await repository.recoverExpiredTargetHandover();
    expect(becameWriter, isFalse);
    expect(registrationRequests, hasLength(2));
    expect(
      registrationRequests.every(
        (request) => request['takeOverWriting'] == false,
      ),
      isTrue,
    );
    expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
    expect(secretStore.value, isNull);
    api.close();
    await database.close();
  });

  test('completed inactive target clears obsolete secret after readonly registration', () async {
    handoverCompleteActiveWriter = false;
    activeWriter = false;
    final secretStore = _MemoryPendingHandoverSecretStore();
    final (store, database, api, repository) = await fixture(
      handoverSecrets: secretStore,
    );
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    secretStore.value = PendingHandoverRecord(
      apiOrigin: api.configuration.canonicalApiOrigin,
      accountId: accountId,
      requestId: 'f1234567-1234-4234-8234-123456789abc',
      sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
      targetClientId: clientId,
      handoverId: 'f1234567-1234-4234-8234-123456789abc',
      phase: 'targetCompletePending',
      frozenRevision: 1,
      expiresAtUtc: expiry,
      oneTimeCode: 'target-one-time-code',
    ).encode();
    await store.freezeWritesIfOutboxEmpty();

    final becameWriter = await repository.recoverExpiredTargetHandover();

    expect(becameWriter, isFalse);
    expect(handoverCompleteRequests, hasLength(1));
    expect(registrationRequests, hasLength(2));
    expect(
      registrationRequests.every(
        (request) => request['takeOverWriting'] == false,
      ),
      isTrue,
    );
    expect(secretStore.value, isNull);
    expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
    api.close();
    await database.close();
  });

  test(
    'failed catch-up pull sends no completion and keeps expired target frozen',
    () async {
      pullFailureCode = 'temporary_unavailable';
      pullFailureStatus = 503;
      activeWriter = false;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      final expiry = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      secretStore.value = PendingHandoverRecord(
        apiOrigin: api.configuration.canonicalApiOrigin,
        accountId: accountId,
        requestId: 'f1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
        targetClientId: clientId,
        handoverId: 'f1234567-1234-4234-8234-123456789abc',
        phase: 'targetCompletePending',
        frozenRevision: 7,
        expiresAtUtc: expiry,
        oneTimeCode: 'target-one-time-code',
      ).encode();
      await store.freezeWritesIfOutboxEmpty();

      await expectLater(
        repository.recoverExpiredTargetHandover(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            503,
          ),
        ),
      );

      expect(handoverCompleteRequests, isEmpty);
      expect(await store.readSyncMetadata('pull-cursor'), isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
      expect(secretStore.value, isNotNull);
      expect(registrationRequests.single['takeOverWriting'], isFalse);
      api.close();
      await database.close();
    },
  );

  test(
    'ambiguous completion failure preserves secure identity and write freeze',
    () async {
      handoverCompleteStatus = 503;
      handoverCompleteFailureCode = 'temporary_unavailable';
      activeWriter = false;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      final expiry = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      secretStore.value = PendingHandoverRecord(
        apiOrigin: api.configuration.canonicalApiOrigin,
        accountId: accountId,
        requestId: 'f1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
        targetClientId: clientId,
        handoverId: 'f1234567-1234-4234-8234-123456789abc',
        phase: 'targetCompletePending',
        frozenRevision: 1,
        expiresAtUtc: expiry,
        oneTimeCode: 'target-one-time-code',
      ).encode();
      await store.freezeWritesIfOutboxEmpty();

      await expectLater(
        repository.recoverExpiredTargetHandover(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            503,
          ),
        ),
      );
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
      expect(secretStore.value, isNotNull);
      api.close();
      await database.close();
    },
  );

  for (final (label, status, code) in [
    // Status codes as the API sends them (SyncHandoverService).
    ('wrong code', 409, 'invalid_handover_code'),
    ('wrong id', 404, 'handover_not_found'),
    ('invalid request', 422, 'invalid_handover_request'),
    ('same device as target', 409, 'invalid_handover_target'),
  ]) {
    test('definitive $label on complete releases freeze and record, '
        'a corrected entry is then accepted', () async {
      handoverCompleteStatus = status;
      handoverCompleteFailureCode = code;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      Future<void> complete(String oneTimeCode) => repository
          .completeHandover(
            handoverId: 'f1234567-1234-4234-8234-123456789abc',
            oneTimeCode: oneTimeCode,
            frozenRevision: 1,
            sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
            expiresAtUtc: DateTime.now().toUtc().add(
              const Duration(minutes: 10),
            ),
          )
          .then((_) {});

      await expectLater(
        complete('wrong-code'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
      expect(secretStore.value, isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isFalse);

      handoverCompleteStatus = 200;
      await complete('target-one-time-code');
      expect(
        handoverCompleteRequests.last['oneTimeCode'],
        'target-one-time-code',
      );
      expect(secretStore.value, isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isFalse);
      api.close();
      await database.close();
    });
  }

  test('a bare 400 without a handover code keeps record and freeze', () async {
    handoverCompleteStatus = 400;
    handoverCompleteFailureCode = 'bad_gateway_html';
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
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(secretStore.value, isNotNull);
    expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
    api.close();
    await database.close();
  });

  test(
    'a rejection does not unfreeze a device that was already frozen',
    () async {
      handoverCompleteStatus = 409;
      handoverCompleteFailureCode = 'invalid_handover_code';
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      await store.freezeWritesIfOutboxEmpty();
      await expectLater(
        repository.completeHandover(
          handoverId: 'f1234567-1234-4234-8234-123456789abc',
          oneTimeCode: 'wrong-code',
          frozenRevision: 1,
          sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(secretStore.value, isNull);
      expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
      api.close();
      await database.close();
    },
  );

  test(
    'a legacy record with a far-future expiry can still be recovered',
    () async {
      handoverCompleteStatus = 409;
      handoverCompleteFailureCode = 'handover_expired';
      activeWriter = false;
      final secretStore = _MemoryPendingHandoverSecretStore();
      final (store, database, api, repository) = await fixture(
        handoverSecrets: secretStore,
      );
      secretStore.value = PendingHandoverRecord(
        apiOrigin: api.configuration.canonicalApiOrigin,
        accountId: accountId,
        requestId: 'f1234567-1234-4234-8234-123456789abc',
        sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
        targetClientId: clientId,
        handoverId: 'f1234567-1234-4234-8234-123456789abc',
        phase: 'targetCompletePending',
        frozenRevision: 1,
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 3650)),
        oneTimeCode: 'target-one-time-code',
      ).encode();
      await store.freezeWritesIfOutboxEmpty();

      expect(await repository.recoverExpiredTargetHandover(), isFalse);
      expect(secretStore.value, isNull);
      api.close();
      await database.close();
    },
  );

  test('transient completion failure keeps the record but caps a far-future '
      'expiry to the server lifetime', () async {
    handoverCompleteStatus = 503;
    handoverCompleteFailureCode = 'temporary_unavailable';
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
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 3650)),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(await store.readSyncMetadata('local-writes-frozen'), isTrue);
    final stored = PendingHandoverRecord.decode(secretStore.value!);
    expect(
      stored.expiresAtUtc!.isBefore(
        DateTime.now().toUtc().add(const Duration(minutes: 16)),
      ),
      isTrue,
    );
    api.close();
    await database.close();
  });

  test('recovery treats 404 handover_not_found as terminal', () async {
    handoverCompleteStatus = 404;
    handoverCompleteFailureCode = 'handover_not_found';
    activeWriter = false;
    final secretStore = _MemoryPendingHandoverSecretStore();
    final (store, database, api, repository) = await fixture(
      handoverSecrets: secretStore,
    );
    secretStore.value = PendingHandoverRecord(
      apiOrigin: api.configuration.canonicalApiOrigin,
      accountId: accountId,
      requestId: 'f1234567-1234-4234-8234-123456789abc',
      sourceClientId: 'e1234567-1234-4234-8234-123456789abc',
      targetClientId: clientId,
      handoverId: 'f1234567-1234-4234-8234-123456789abc',
      phase: 'targetCompletePending',
      frozenRevision: 1,
      expiresAtUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      oneTimeCode: 'target-one-time-code',
    ).encode();
    await store.freezeWritesIfOutboxEmpty();

    expect(await repository.recoverExpiredTargetHandover(), isFalse);
    expect(secretStore.value, isNull);
    api.close();
    await database.close();
  });
}

Future<String> _readBody(HttpRequest request) async =>
    await utf8.decoder.bind(request).join();

class _SyncTimerStub implements Timer {
  _SyncTimerStub(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

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
