import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/water_intake_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';

const _accountId = 'b1234567-1234-4234-8234-123456789abc';
const _clientId = 'e1234567-1234-4234-8234-123456789abc';
const _day = '2026-10-12';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

final _serverNutritionDayId = _id(0xa00);
final _serverWaterDayId = _id(0xa01);
final _serverEntryId = _id(0xa02);
final _localEntryId = _id(0xb01);

Map<String, Object?> _entryJson(String entryId, String name) => {
  'entryId': entryId,
  'meal': 'Breakfast',
  'position': 0,
  'productName': name,
  'brand': null,
  'amountGrams': 100,
  'totals': {'kilocalories': 100},
  'per100Grams': {'kilocalories': 100},
  'source': null,
};

/// Ein offline angelegter Ernährungs- oder Wassertag trifft beim Pull auf den
/// Servertag desselben Datums unter anderer ID (#298). Der Server erlaubt
/// einen Tag je Datum und lehnt eine zweite Anlage dauerhaft ab.
void main() {
  late HttpServer server;
  late LocalDatabase database;
  late LocalSyncStore store;
  late ApiClient api;
  late SyncRepository sync;
  late NutritionRepository nutrition;
  late WaterIntakeRepository water;
  late List<Map<String, dynamic>> mutations;
  late bool activeWriter;
  var counter = 0x400;
  var serverEntryCount = 1;

  Map<String, dynamic> serverBatch() => {
    'batchId': _id(0x901),
    'revision': 1,
    'originMutationId': _id(0xc01),
    'changes': [
      {
        'resourceType': 'NutritionDay',
        'resourceId': _serverNutritionDayId,
        'version': 3,
        'isTombstone': false,
        'snapshot': {
          'nutritionDayId': _serverNutritionDayId,
          'localDate': _day,
          'entries': [
            _entryJson(_serverEntryId, 'Server'),
            for (var index = 1; index < serverEntryCount; index++)
              {
                ..._entryJson(_id(0x1000 + index), 'Server $index'),
                'position': index,
              },
          ],
          'createdAtUtc': '2026-10-12T06:00:00Z',
          'updatedAtUtc': '2026-10-12T06:00:00Z',
          'version': 3,
        },
      },
      {
        'resourceType': 'WaterIntakeDay',
        'resourceId': _serverWaterDayId,
        'version': 3,
        'isTombstone': false,
        'snapshot': {
          'waterIntakeDayId': _serverWaterDayId,
          'localDate': _day,
          'amountMl': 900,
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
    if ((mutation['payload'] as Map)['baseVersion'] == 0) {
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

  Future<void> handle(HttpRequest request) async {
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
  }

  setUp(() async {
    counter = 0x400;
    mutations = [];
    activeWriter = true;
    serverEntryCount = 1;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
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
    String ids() => _id(counter++);
    DateTime clock() => DateTime.utc(2026, 10, 12, 9);
    nutrition = NutritionRepository(store: store, ids: ids, clock: clock);
    water = WaterIntakeRepository(store: store, ids: ids, clock: clock);
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    await database.close();
  });

  Future<void> saveOffline() async {
    await nutrition.saveEntry(
      _day,
      NutritionEntry.fromJson(_entryJson(_localEntryId, 'Lokal')),
    );
    await water.add(_day, 200);
  }

  /// Genau eine Zeile (die des Servers) je Typ und genau ein sendbarer
  /// Eintrag: Änderung von Version 3.
  Future<void> expectAdopted(String aggregateType, String serverId) async {
    final rows = await store.readAggregates(aggregateType);
    expect(rows.map((row) => row.aggregateId), [serverId]);
    final waiting = (await store.readOutbox(aggregateType: aggregateType))
        .single;
    expect(waiting.aggregateId, serverId);
    expect(waiting.status, LocalMutationStatus.pending);
    expect(waiting.operation, LocalMutationOperation.update);
    expect(waiting.baseVersion, 3);
  }

  Future<void> expectBothAdopted() async {
    await expectAdopted('nutrition-day', _serverNutritionDayId);
    await expectAdopted(waterIntakeAggregateType, _serverWaterDayId);
    expect(await sync.readConflicts(), isEmpty);
    final entries = (await nutrition.read(_day)).day.entries;
    expect(entries.map((entry) => entry.entryId), [
      _serverEntryId,
      _localEntryId,
    ]);
    expect(entries.map((entry) => entry.position), [0, 1]);
    expect(await water.read(_day), 1100);
  }

  test('ein Ernährungstag über 200 Einträgen wird nicht übernommen', () async {
    activeWriter = false;
    serverEntryCount = 200;
    await saveOffline();
    final localId = (await store.readAggregates('nutrition-day'))
        .single
        .aggregateId;

    await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

    final rows = await store.readAggregates('nutrition-day');
    expect(rows.map((row) => row.aggregateId).toSet(), {
      localId,
      _serverNutritionDayId,
    });
    final waiting = (await store.readOutbox(aggregateType: 'nutrition-day'))
        .single;
    expect(waiting.aggregateId, localId);
    expect(waiting.operation, LocalMutationOperation.create);
    final server = rows.singleWhere(
      (row) => row.aggregateId == _serverNutritionDayId,
    );
    expect(server.serverVersion, 3);
    expect((server.workingCopy! as Map)['entries'], hasLength(200));
  });

  test('eine lokal gesetzte Wassermenge gilt als Tagessumme', () async {
    activeWriter = false;
    await water.add(_day, 200);
    await water.setAmount(_day, 300);
    await water.add(_day, 50);

    await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

    await expectAdopted(waterIntakeAggregateType, _serverWaterDayId);
    expect(await water.read(_day), 350);
    final waiting = (await store.readOutbox(
      aggregateType: waterIntakeAggregateType,
    )).single;
    expect((waiting.body! as Map).containsKey('amountSetLocally'), isFalse);
  });

  test(
    'nicht gesendete Tage werden zu Änderungen der gezogenen Tage',
    () async {
      activeWriter = false;
      await saveOffline();

      await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

      expect(mutations, isEmpty);
      await expectBothAdopted();
    },
  );

  test('abgelehnte Tage werden beim Pull übernommen und als Änderung '
      'gesendet', () async {
    await saveOffline();

    await sync.synchronize(now: DateTime.utc(2026, 10, 12, 10));

    expect(mutations.map((mutation) => mutation['operation']).toSet(), {
      'saveNutritionDay',
      'setWaterIntake',
    });
    await expectBothAdopted();

    final report = await sync.synchronize(now: DateTime.utc(2026, 10, 12, 11));

    expect(report.pushed, 2);
    final sent = mutations.skip(2).toList();
    final day =
        sent.singleWhere(
              (mutation) => mutation['operation'] == 'saveNutritionDay',
            )['payload']
            as Map;
    expect(day['nutritionDayId'], _serverNutritionDayId);
    expect(day['baseVersion'], 3);
    expect((day['entries'] as List).map((entry) => entry['entryId']), [
      _serverEntryId,
      _localEntryId,
    ]);
    final drink =
        sent.singleWhere(
              (mutation) => mutation['operation'] == 'setWaterIntake',
            )['payload']
            as Map;
    expect(drink['waterIntakeDayId'], _serverWaterDayId);
    expect(drink['baseVersion'], 3);
    expect(drink['amountMl'], 1100);
  });
}
