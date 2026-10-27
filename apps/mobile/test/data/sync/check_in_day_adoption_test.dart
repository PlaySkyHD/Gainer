import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';

const _accountId = 'b1234567-1234-4234-8234-123456789abc';
const _clientId = 'e1234567-1234-4234-8234-123456789abc';
const _day = '2026-10-12';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

final _serverId = _id(0xa00);

/// Ein offline angelegter Check-in trifft beim Pull auf den Server-Check-in
/// desselben Tages unter anderer ID (#285). Der Server erlaubt einen
/// Check-in je Tag und lehnt eine zweite Anlage dauerhaft ab.
void main() {
  late HttpServer server;
  late LocalDatabase database;
  late LocalSyncStore store;
  late ApiClient api;
  late SyncRepository sync;
  late BodyRepository body;
  late List<Map<String, dynamic>> mutations;
  late bool activeWriter;
  var counter = 0x400;

  Map<String, dynamic> serverBatch() => {
    'batchId': _id(0x901),
    'revision': 1,
    'originMutationId': _id(0xc01),
    'changes': [
      {
        'resourceType': 'DailyCheckIn',
        'resourceId': _serverId,
        'version': 3,
        'isTombstone': false,
        'snapshot': {
          'checkInId': _serverId,
          'localDate': _day,
          'values': {
            'weightKg': 72.0,
            'caloriesKcal': 1800.0,
            'proteinGrams': null,
            'carbohydrateGrams': null,
            'fatGrams': null,
            'steps': 4000,
            'sleepMinutes': null,
          },
          'createdAtUtc': '2026-10-12T06:00:00Z',
          'updatedAtUtc': '2026-10-12T06:00:00Z',
          'version': 3,
        },
      },
    ],
  };

  Future<void> handleMutation(HttpRequest request) async {
    final mutation = jsonDecode(
      await utf8.decoder.bind(request).join(),
    ) as Map<String, dynamic>;
    mutations.add(mutation);
    if (mutation['operation'] == 'createDailyCheckIn') {
      // Unique-Index (UserId, LocalDate): dauerhafte Ablehnung.
      request.response.statusCode = 422;
      request.response.write(
        jsonEncode({'code': 'invalid_payload', 'message': 'Invalid.'}),
      );
      return;
    }
    request.response.write(
      jsonEncode({
        'mutationId': request.uri.pathSegments.last,
        'replayed': false,
        'revision': 1 + mutations.length,
        'resources': [],
      }),
    );
  }

  void handleChanges(HttpRequest request) {
    final after = int.parse(request.uri.queryParameters['after']!);
    final batches = [if (after < 1) serverBatch()];
    request.response.write(
      jsonEncode({
        'protocolVersion': nativeSyncProtocolVersion,
        'nextCursor': batches.isEmpty ? after : 1,
        'hasMore': false,
        'batches': batches,
      }),
    );
  }

  setUp(() async {
    counter = 0x400;
    mutations = [];
    activeWriter = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (path == '/api/v1/auth/session') {
        request.response.write(
          jsonEncode({
            'userId': _accountId,
            'email': 'fixture@example.test',
            'isAccountOperator': false,
          }),
        );
      } else if (path.startsWith('/api/v1/sync/clients/')) {
        await utf8.decoder.bind(request).join();
        request.response.write(
          jsonEncode({
            'clientId': _clientId,
            'displayName': 'Gainer iPhone',
            'protocolVersion': nativeSyncProtocolVersion,
            'isActiveWriter': activeWriter,
            'registeredAtUtc': '2026-10-12T08:00:00Z',
            'lastSeenAtUtc': '2026-10-12T08:00:00Z',
          }),
        );
      } else if (path.startsWith('/api/v1/sync/mutations/')) {
        await handleMutation(request);
      } else if (path == '/api/v1/sync/changes') {
        handleChanges(request);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    database = LocalDatabase(NativeDatabase.memory());
    store = LocalSyncStore(database: database, accountId: _accountId);
    await database
        .into(database.installationMetadata)
        .insertOnConflictUpdate(
          InstallationMetadataCompanion.insert(
            key: 'installation-id',
            value: _clientId,
          ),
        );
    api = ApiClient(
      configuration: ApiConfiguration(
        apiOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
        allowInsecureLoopbackForDevelopment: true,
      ),
    );
    sync = SyncRepository(
      store: store,
      api: api,
      installationIdentity: InstallationIdentityStore(database),
      displayName: 'Gainer iPhone',
    );
    body = BodyRepository(
      store: store,
      ids: () => _id(counter++),
      clock: () => DateTime.utc(2026, 10, 12, 9),
    );
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    await database.close();
  });

  Future<String> saveOffline() => body.saveCheckIn(
    const DailyCheckInInput(
      localDate: _day,
      weightKg: 71,
      caloriesKcal: 2500,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
      steps: null,
      sleepMinutes: null,
    ),
  );

  /// Genau eine Zeile (die des Servers) mit den lokalen Werten und genau ein
  /// sendbarer Eintrag: Korrektur von Version 3.
  Future<void> expectAdopted() async {
    final rows = await store.readAggregates('daily-check-in');
    expect(rows.map((row) => row.aggregateId), [_serverId]);
    final waiting = (await store.readOutbox(aggregateType: 'daily-check-in'))
        .single;
    expect(waiting.aggregateId, _serverId);
    expect(waiting.status, LocalMutationStatus.pending);
    expect(waiting.operation, LocalMutationOperation.update);
    expect(waiting.baseVersion, 3);
    expect(await sync.readConflicts(), isEmpty);
    final value = (await body.read()).checkIns.single.value;
    expect(value.weightKg, 71);
    expect(value.caloriesKcal, 2500);
    expect(value.steps, 4000);
    expect(value.createdAtUtc, '2026-10-12T06:00:00Z');
  }

  test('ein nicht gesendeter Check-in wird zur Korrektur des gezogenen '
      'Check-ins', () async {
    activeWriter = false;
    final localId = await saveOffline();
    expect(localId, isNot(_serverId));

    await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

    expect(mutations, isEmpty);
    await expectAdopted();
  });

  test('ein abgelehnter Check-in wird beim Pull übernommen und als Korrektur '
      'gesendet', () async {
    await saveOffline();

    await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

    expect(mutations.single['operation'], 'createDailyCheckIn');
    await expectAdopted();

    final report = await sync.synchronize(now: DateTime.utc(2026, 10, 12, 11));

    expect(report.pushed, 1);
    expect(mutations.last['operation'], 'correctDailyCheckIn');
    expect(mutations.last['payload'], containsPair('checkInId', _serverId));
    expect(mutations.last['payload'], containsPair('baseVersion', 3));
    expect(
      (mutations.last['payload'] as Map)['values'],
      containsPair('weightKg', 71.0),
    );
  });
}
