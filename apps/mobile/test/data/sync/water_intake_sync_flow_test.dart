import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/water_intake_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountId = 'b1234567-1234-4234-8234-123456789abc';
const _clientId = 'e1234567-1234-4234-8234-123456789abc';
const _day = '2026-10-25';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

/// Push und Pull der Wassermenge gegen einen Fake-Server.
void main() {
  late HttpServer server;
  late LocalDatabase database;
  late LocalSyncStore store;
  late ApiClient api;
  late SyncRepository sync;
  late WaterIntakeRepository water;
  late List<Map<String, dynamic>> mutations;
  late List<Map<String, dynamic>> pullBatches;
  var counter = 0x400;

  setUp(() async {
    counter = 0x400;
    mutations = [];
    pullBatches = [];
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
            'protocolVersion': 3,
            'isActiveWriter': true,
            'registeredAtUtc': '2026-10-25T08:00:00Z',
            'lastSeenAtUtc': '2026-10-25T08:00:00Z',
          }),
        );
      } else if (path.startsWith('/api/v1/sync/mutations/')) {
        mutations.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.write(
          jsonEncode({
            'mutationId': path.split('/').last,
            'replayed': false,
            'revision': mutations.length,
            'resources': [],
          }),
        );
      } else if (path == '/api/v1/sync/changes') {
        final after = int.parse(request.uri.queryParameters['after']!);
        final batches = [
          for (final batch in pullBatches)
            if ((batch['revision'] as int) > after) batch,
        ];
        request.response.write(
          jsonEncode({
            'protocolVersion': 3,
            'nextCursor': batches.isEmpty
                ? after
                : batches.last['revision'] as int,
            'hasMore': false,
            'batches': batches,
          }),
        );
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
    water = WaterIntakeRepository(
      store: store,
      ids: () => _id(counter++),
      clock: () => DateTime.utc(2026, 10, 25, 9),
    );
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    await database.close();
  });

  Map<String, dynamic> serverDay(String id, int amountMl, int version) => {
    'waterIntakeDayId': id,
    'localDate': _day,
    'amountMl': amountMl,
    'createdAtUtc': '2026-10-25T09:00:00Z',
    'updatedAtUtc': '2026-10-25T09:00:00Z',
    'version': version,
  };

  test('offline taps go out as one total, later taps as additions', () async {
    await water.add(_day, 500);
    await water.add(_day, 500);
    final waiting = (await store.readOutbox()).single;
    pullBatches = [
      {
        'batchId': _id(0x900),
        'revision': 1,
        'originMutationId': waiting.mutationId,
        'changes': [
          {
            'resourceType': 'WaterIntakeDay',
            'resourceId': waiting.aggregateId,
            'version': 1,
            'isTombstone': false,
            'snapshot': serverDay(waiting.aggregateId, 1000, 1),
          },
        ],
      },
    ];

    final first = await sync.synchronize(now: DateTime.utc(2026, 10, 25, 9));

    expect(first.pushed, 1);
    expect(mutations.single['operation'], 'setWaterIntake');
    expect(mutations.single['resources'], [
      {
        'resourceType': 'WaterIntakeDay',
        'resourceId': waiting.aggregateId,
        'baseVersion': 0,
      },
    ]);
    expect(mutations.single['payload'], {
      'waterIntakeDayId': waiting.aggregateId,
      'localDate': _day,
      'baseVersion': 0,
      'amountMl': 1000,
    });
    final confirmed = await store.readAggregate(
      waterIntakeAggregateType,
      waiting.aggregateId,
    );
    expect(confirmed!.serverVersion, 1);
    expect(await water.read(_day), 1000);

    await water.add(_day, 200);
    final second = await sync.synchronize(now: DateTime.utc(2026, 10, 25, 10));

    expect(second.pushed, 1);
    expect(mutations.last['operation'], 'addWaterIntake');
    expect(mutations.last['payload'], containsPair('baseVersion', 1));
    expect(mutations.last['payload'], containsPair('amountMl', 200));
  });

  test('a day from another device is pulled into the local store', () async {
    final id = _id(0x777);
    pullBatches = [
      {
        'batchId': _id(0x901),
        'revision': 1,
        'originMutationId': null,
        'changes': [
          {
            'resourceType': 'WaterIntakeDay',
            'resourceId': id,
            'version': 3,
            'isTombstone': false,
            'snapshot': serverDay(id, 1750, 3),
          },
        ],
      },
    ];

    await sync.synchronize(now: DateTime.utc(2026, 10, 25, 9));

    expect(await water.read(_day), 1750);
    final envelope = await store.readAggregate(waterIntakeAggregateType, id);
    expect(envelope!.serverVersion, 3);
    expect((envelope.workingCopy! as Map).containsKey('version'), isFalse);
  });
}
