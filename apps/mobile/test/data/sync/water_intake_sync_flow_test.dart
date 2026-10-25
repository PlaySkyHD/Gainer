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

/// Push und Pull der Wassermenge gegen einen Fake-Server, der wie der echte
/// Server Wasser nur an Clients ab Protokoll 4 ausliefert.
void main() {
  late HttpServer server;
  late LocalDatabase database;
  late LocalSyncStore store;
  late ApiClient api;
  late SyncRepository sync;
  late WaterIntakeRepository water;
  late List<Map<String, dynamic>> mutations;
  late List<Map<String, dynamic>> pullBatches;
  late List<String?> pullProtocols;
  var counter = 0x400;

  setUp(() async {
    counter = 0x400;
    mutations = [];
    pullBatches = [];
    pullProtocols = [];
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
        final requested = request.uri.queryParameters['protocolVersion'];
        pullProtocols.add(requested);
        final protocol = int.tryParse(requested ?? '') ?? 3;
        final batches = [
          for (final batch in pullBatches)
            if ((batch['revision'] as int) > after) batch,
        ];
        final hasWater = batches.any(
          (batch) => (batch['changes'] as List).any(
            (change) => (change as Map)['resourceType'] == 'WaterIntakeDay',
          ),
        );
        if (protocol < 4 && hasWater) {
          request.response.statusCode = 409;
          request.response.write(
            jsonEncode({'code': 'upgrade_required', 'message': 'Update'}),
          );
        } else {
          request.response.write(
            jsonEncode({
              'protocolVersion': protocol,
              'nextCursor': batches.isEmpty
                  ? after
                  : batches.last['revision'] as int,
              'hasMore': false,
              'batches': batches,
            }),
          );
        }
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

  Map<String, dynamic> batch(
    int revision,
    String id,
    int amountMl,
    int version, {
    String? origin,
  }) => {
    'batchId': _id(0x900 + revision),
    'revision': revision,
    'originMutationId': origin,
    'changes': [
      {
        'resourceType': 'WaterIntakeDay',
        'resourceId': id,
        'version': version,
        'isTombstone': false,
        'snapshot': serverDay(id, amountMl, version),
      },
    ],
  };

  test(
    'every change goes out as the day total on the server version',
    () async {
      final dayId = waterIntakeDayId(_accountId, _day);
      await water.add(_day, 500);
      await water.add(_day, 500);
      final waiting = (await store.readOutbox()).single;
      expect(waiting.aggregateId, dayId);
      pullBatches = [batch(1, dayId, 1000, 1, origin: waiting.mutationId)];

      final first = await sync.synchronize(now: DateTime.utc(2026, 10, 25, 9));

      expect(first.pushed, 1);
      expect(mutations.single['operation'], 'setWaterIntake');
      expect(mutations.single['resources'], [
        {
          'resourceType': 'WaterIntakeDay',
          'resourceId': dayId,
          'baseVersion': 0,
        },
      ]);
      expect(mutations.single['payload'], {
        'waterIntakeDayId': dayId,
        'localDate': _day,
        'baseVersion': 0,
        'amountMl': 1000,
      });
      expect(pullProtocols, everyElement('$nativeSyncProtocolVersion'));
      final confirmed = await store.readAggregate(
        waterIntakeAggregateType,
        dayId,
      );
      expect(confirmed!.serverVersion, 1);
      expect(await water.read(_day), 1000);

      await water.add(_day, 200);
      final second = await sync.synchronize(
        now: DateTime.utc(2026, 10, 25, 10),
      );

      expect(second.pushed, 1);
      expect(mutations.last['operation'], 'setWaterIntake');
      expect(mutations.last['payload'], containsPair('baseVersion', 1));
      expect(mutations.last['payload'], containsPair('amountMl', 1200));
    },
  );

  test('another device writes the same day under the same id', () async {
    final dayId = waterIntakeDayId(_accountId, _day);
    pullBatches = [batch(1, dayId, 1750, 3)];

    final report = await sync.synchronize(now: DateTime.utc(2026, 10, 25, 9));

    expect(report.state, isNot(SyncRunState.upgradeRequired));
    expect(await water.read(_day), 1750);
    final envelope = await store.readAggregate(waterIntakeAggregateType, dayId);
    expect(envelope!.serverVersion, 3);
    expect((envelope.workingCopy! as Map).containsKey('version'), isFalse);

    // Weiter von dieser Version aus, ohne zweite ID für denselben Tag.
    await water.add(_day, 250);
    final next = (await store.readOutbox()).single;
    expect(next.aggregateId, dayId);
    expect(next.baseVersion, 3);
  });

  test('ids are fixed per account and day', () {
    expect(
      waterIntakeDayId(_accountId, _day),
      waterIntakeDayId(_accountId, _day),
    );
    expect(
      waterIntakeDayId(_accountId.toUpperCase(), _day),
      waterIntakeDayId(_accountId, _day),
    );
    expect(
      waterIntakeDayId(_accountId, _day),
      isNot(waterIntakeDayId(_accountId, '2026-10-26')),
    );
    expect(
      waterIntakeDayId(_accountId, _day),
      isNot(waterIntakeDayId(_clientId, _day)),
    );
    expect(
      waterIntakeDayId(_accountId, _day),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
