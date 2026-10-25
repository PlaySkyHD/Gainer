import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/local/local_aggregate.dart';
import 'package:gainer_mobile/data/models/local/local_mutation.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_payload_codec.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_repository.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

const _accountId = 'a1234567-1234-4234-8234-123456789abc';
const _clientId = 'd1234567-1234-4234-8234-123456789abc';
const _squat = '00000000-0000-4000-8000-0000000000a1';

String _id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _Catalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [
      CatalogExercise(
        id: _squat,
        name: 'Kniebeuge',
        exerciseType: ExerciseKind.strength,
        isBase: true,
      ),
    ],
    categories: [],
  );
}

/// Antwort des Fake-Servers auf eine Mutation; `null` heißt angenommen.
typedef _Rejection = ({int status, String code});

void main() {
  late HttpServer server;
  late LocalDatabase database;
  late LocalSyncStore store;
  late ApiClient api;
  late SyncRepository sync;
  late TrainingLogRepository training;
  late List<Map<String, dynamic>> mutations;
  late List<Map<String, dynamic>> pullBatches;
  Future<_Rejection?> Function(Map<String, dynamic> body, int index)?
  onMutation;
  var now = DateTime.utc(2026, 10, 17, 8);
  var counter = 0x100;
  String nextId() => _id(counter++);

  setUp(() async {
    counter = 0x100;
    now = DateTime.utc(2026, 10, 17, 8);
    mutations = [];
    pullBatches = [];
    onMutation = null;
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
            'registeredAtUtc': '2026-10-12T10:00:00Z',
            'lastSeenAtUtc': '2026-10-12T10:00:00Z',
          }),
        );
      } else if (path.startsWith('/api/v1/sync/mutations/')) {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        mutations.add(body);
        final rejection = await onMutation?.call(body, mutations.length - 1);
        if (rejection != null) {
          request.response.statusCode = rejection.status;
          request.response.write(
            jsonEncode({'code': rejection.code, 'message': 'abgelehnt'}),
          );
        } else {
          request.response.write(
            jsonEncode({
              'mutationId': path.split('/').last,
              'replayed': false,
              'revision': 1,
              'resources': [],
            }),
          );
        }
      } else if (path == '/api/v1/sync/changes') {
        final after = int.parse(request.uri.queryParameters['after']!);
        final batches = [
          for (final batch in pullBatches)
            if ((batch['revision'] as int) > after) batch,
        ];
        request.response.write(
          jsonEncode({
            'protocolVersion': nativeSyncProtocolVersion,
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
    training = TrainingLogRepository(
      store: store,
      catalog: _Catalog(),
      ids: nextId,
      clock: () => now,
    );
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    await database.close();
  });

  WorkoutBlock block(String exerciseId) => WorkoutBlock(
    workoutExerciseId: nextId(),
    sourceExerciseId: exerciseId,
    exerciseNameSnapshot: 'Übung',
    exerciseTypeSnapshot: ExerciseKind.strength,
    sets: [LoggedSet(setId: nextId(), weightKg: 80, repetitions: 5)],
  );

  Future<Workout> startAndLog(String exerciseId) async {
    final started = await training.startEmpty(title: 'Beine');
    return training.saveWorkout(
      started.copyWith(exercises: [block(exerciseId)]),
    );
  }

  Future<int> conflictCount() async =>
      (await database.select(database.localConflicts).get()).length;

  List<String> sentOperations() => [
    for (final mutation in mutations) mutation['operation'] as String,
  ];

  group('offline workout', () {
    test(
      'start, log and finish leave exactly one create with the ended workout',
      () async {
        final workout = await startAndLog(_squat);
        now = now.add(const Duration(minutes: 45));
        await training.finishWorkout(workout.workoutId);

        final outbox = await store.readOutbox();
        expect(outbox, hasLength(1));
        expect(outbox.single.operation, LocalMutationOperation.create);
        expect((outbox.single.body as Map)['endedAtUtc'], isNotNull);

        final report = await sync.synchronize(now: now);

        expect(report.pushed, 1);
        expect(sentOperations(), ['createWorkout']);
        expect(
          (mutations.single['payload']['workout'] as Map)['endedAtUtc'],
          isNotNull,
        );
        expect(await conflictCount(), 0);
      },
    );

    test('start and delete before sending sends nothing at all', () async {
      final workout = await startAndLog(_squat);
      await training.deleteWorkout(workout.workoutId);

      expect(await store.readOutbox(), isEmpty);
      expect(await training.readDiary(), isEmpty);
      expect(await training.readWorkout(workout.workoutId), isNull);
      expect(await training.readActiveWorkout(), isNull);

      final report = await sync.synchronize(now: now);

      expect(report.pushed, 0);
      expect(mutations, isEmpty);
    });
  });

  group('self-healing (D2)', () {
    test('active_workout_exists with a newer local state sends it once, no conflict', () async {
      final workout = await startAndLog(_squat);
      onMutation = (body, index) async {
        if (index == 0) {
          // Während die Anlage unterwegs ist, wird das Training beendet.
          now = now.add(const Duration(minutes: 30));
          await training.finishWorkout(workout.workoutId);
          return (status: 409, code: 'active_workout_exists');
        }
        return null;
      };

      final report = await sync.synchronize(now: now);

      expect(sentOperations(), ['createWorkout', 'createWorkout']);
      expect(
        (mutations.first['payload']['workout'] as Map)['endedAtUtc'],
        isNull,
      );
      expect(
        (mutations.last['payload']['workout'] as Map)['endedAtUtc'],
        isNotNull,
      );
      expect(report.pushed, 1);
      expect(await conflictCount(), 0);
      final outbox = await store.readOutbox();
      expect(outbox.single.status, LocalMutationStatus.clean);
    });

    test(
      'a workout deleted locally and unknown to the server is cleaned up',
      () async {
        final workout = await startAndLog(_squat);
        onMutation = (body, index) async {
          await training.deleteWorkout(workout.workoutId);
          return (status: 409, code: 'active_workout_exists');
        };

        await sync.synchronize(now: now);

        expect(mutations, hasLength(1));
        expect(await conflictCount(), 0);
        expect(await store.readOutbox(), isEmpty);
        expect(await store.readAggregate('workout', workout.workoutId), isNull);
        expect(await training.readDiary(), isEmpty);
      },
    );

    test('the same rejection of the same resource heals only once', () async {
      final workout = await startAndLog(_squat);
      onMutation = (body, index) async {
        // Jede Antwort kommt, nachdem der Nutzer weiter geändert hat.
        now = now.add(const Duration(minutes: 1));
        final current = (await training.readWorkout(workout.workoutId))!;
        await training.saveWorkout(current.copyWith(title: 'Beine $index'));
        return (status: 409, code: 'active_workout_exists');
      };

      await sync.synchronize(now: now);

      expect(mutations, hasLength(2));
      final conflicts = await database.select(database.localConflicts).get();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.code, 'active_workout_exists');
      // Weitere Läufe senden nichts mehr, bis der Nutzer entscheidet.
      await sync.synchronize(now: now);
      expect(mutations, hasLength(2));
    });

    test(
      'a rejection that the local state does not explain stays a conflict',
      () async {
        await startAndLog(_squat);
        onMutation = (body, index) async =>
            (status: 409, code: 'active_workout_exists');

        await sync.synchronize(now: now);

        expect(mutations, hasLength(1));
        expect(await conflictCount(), 1);
      },
    );

    Future<(String, Map<String, Object?>)> seedServerPlan() async {
      final planId = nextId();
      final plan = TrainingPlanModel(
        planId: planId,
        name: 'Push',
        previousValueSource: PreviousValueSource.plan,
        entries: const [],
      ).toJson();
      await store.ensureAccountBound();
      await database
          .into(database.localResources)
          .insertOnConflictUpdate(
            LocalResourcesCompanion.insert(
              aggregateType: 'training-plan',
              aggregateId: planId,
              envelopeJson: serverEnvelope(
                aggregateId: planId,
                snapshot: plan,
                version: 1,
              ).encode(),
              updatedAtEpochMs: 0,
            ),
          );
      return (planId, plan);
    }

    Future<void> editPlan(
      String planId,
      Map<String, Object?> plan,
      String name,
    ) async {
      final old = (await store.readAggregate('training-plan', planId))!;
      final body = {...plan, 'name': name};
      await store.commitMutation(
        mutationId: nextId(),
        aggregateType: 'training-plan',
        aggregateId: planId,
        operation: LocalMutationOperation.update,
        baseVersion: old.serverVersion,
        body: body,
        envelope: LocalAggregateEnvelope<Object?>(
          aggregateId: planId,
          serverSnapshot: old.serverSnapshot,
          workingCopy: body,
          serverVersion: old.serverVersion,
          optimisticVersion: old.optimisticVersion + 1,
          syncState: LocalSyncState.pending,
        ),
        createdAtUtc: now,
      );
    }

    test('stale_base_version with a newer local state and no foreign change is resent', () async {
      final (planId, plan) = await seedServerPlan();
      await editPlan(planId, plan, 'Push A');
      onMutation = (body, index) async {
        if (index == 0) {
          await editPlan(planId, plan, 'Push B');
          return (status: 409, code: 'stale_base_version');
        }
        return null;
      };

      final report = await sync.synchronize(now: now);

      expect(sentOperations(), ['updateTrainingPlan', 'updateTrainingPlan']);
      expect(mutations.last['payload']['plan']['name'], 'Push B');
      expect(mutations.last['resources'].single['baseVersion'], 1);
      expect(report.pushed, 1);
      expect(await conflictCount(), 0);
    });

    test(
      'stale_base_version after a change by another device stays a conflict',
      () async {
        final (planId, plan) = await seedServerPlan();
        await editPlan(planId, plan, 'Push A');
        pullBatches = [
          {
            'batchId': nextId(),
            'revision': 1,
            'originMutationId': null,
            'changes': [
              {
                'resourceType': 'TrainingPlan',
                'resourceId': planId,
                'version': 2,
                'isTombstone': false,
                'snapshot': {...plan, 'name': 'Push (anderes Gerät)'},
              },
            ],
          },
        ];
        onMutation = (body, index) async {
          await editPlan(planId, plan, 'Push B');
          return (status: 409, code: 'stale_base_version');
        };

        await sync.synchronize(now: now);

        expect(mutations, hasLength(1));
        final conflicts = await database.select(database.localConflicts).get();
        expect(conflicts.single.code, 'stale_base_version');
        expect(jsonDecode(conflicts.single.detailJson)['foreignChange'], true);
      },
    );

    test('validation_failed on a reference whose create waits goes back to pending', () async {
      final exerciseId = nextId();
      final workout = await startAndLog(exerciseId);
      onMutation = (body, index) async {
        if (index == 0) {
          // Die referenzierte Übung wartet erst jetzt auf ihr Anlegen.
          await training.createCustomExercise(
            CatalogExercise(
              id: exerciseId,
              name: 'Eigene',
              exerciseType: ExerciseKind.strength,
              isBase: false,
            ),
          );
          return (status: 422, code: 'validation_failed');
        }
        return null;
      };

      await sync.synchronize(now: now);
      expect(await conflictCount(), 0);
      final waiting = (await store.readOutbox()).firstWhere(
        (m) => m.aggregateId == workout.workoutId,
      );
      expect(waiting.status, LocalMutationStatus.pending);
      expect(waiting.nextAttemptAtUtc, isNull);

      await sync.synchronize(now: now);

      expect(await conflictCount(), 0);
      expect(sentOperations().last, 'createWorkout');
    });
  });

  group('dependencies (D3)', () {
    Future<(Workout, CatalogExercise)> workoutBeforeExercise() async {
      final exerciseId = nextId();
      // Das Training wurde zuerst angelegt, die Übung danach.
      final workout = await startAndLog(exerciseId);
      now = now.add(const Duration(hours: 1));
      final exercise = await training.createCustomExercise(
        CatalogExercise(
          id: exerciseId,
          name: 'Eigene',
          exerciseType: ExerciseKind.strength,
          isBase: false,
        ),
      );
      return (workout, exercise);
    }

    test('an own exercise is sent before the workout that uses it', () async {
      await workoutBeforeExercise();

      final report = await sync.synchronize(now: now);

      expect(sentOperations(), ['createCustomExercise', 'createWorkout']);
      expect(report.pushed, 2);
      expect(await conflictCount(), 0);
    });

    test('an entry with a waiting reference is skipped without conflict '
        'while the rest goes on', () async {
      final (workout, exercise) = await workoutBeforeExercise();
      final planId = nextId();
      await training.createPlan(
        TrainingPlanModel(
          planId: planId,
          name: 'Ohne Referenz',
          previousValueSource: PreviousValueSource.plan,
          entries: const [],
        ),
      );
      onMutation = (body, index) async =>
          body['operation'] == 'createCustomExercise'
          ? (status: 503, code: 'temporary_unavailable')
          : null;

      final report = await sync.synchronize(now: now);

      expect(sentOperations(), ['createCustomExercise', 'createTrainingPlan']);
      expect(report.pushed, 1);
      expect(await conflictCount(), 0);
      final outbox = await store.readOutbox();
      final skipped = outbox.firstWhere(
        (m) => m.aggregateId == workout.workoutId,
      );
      expect(skipped.status, LocalMutationStatus.pending);
      expect(skipped.attemptCount, 0);
      expect(skipped.nextAttemptAtUtc, isNull);
      final blocked = outbox.firstWhere((m) => m.aggregateId == exercise.id);
      expect(blocked.attemptCount, 1);

      // Sobald die Übung bestätigt ist, folgt das Training.
      onMutation = null;
      await sync.synchronize(now: now.add(const Duration(minutes: 5)));
      expect(sentOperations().sublist(2), [
        'createCustomExercise',
        'createWorkout',
      ]);
    });

    test('an entry whose reference is in conflict is skipped too', () async {
      final (workout, _) = await workoutBeforeExercise();
      onMutation = (body, index) async =>
          body['operation'] == 'createCustomExercise'
          ? (status: 409, code: 'unbekannt')
          : null;

      await sync.synchronize(now: now);
      await sync.synchronize(now: now);

      expect(sentOperations(), ['createCustomExercise']);
      final outbox = await store.readOutbox();
      expect(
        outbox.firstWhere((m) => m.aggregateId == workout.workoutId).status,
        LocalMutationStatus.pending,
      );
      expect(await conflictCount(), 1);
    });

    LocalMutation mutationOf(
      String type,
      Object? body, {
      LocalMutationOperation operation = LocalMutationOperation.update,
      String? id,
    }) => LocalMutation(
      mutationId: _id(1),
      accountId: _accountId,
      aggregateType: type,
      aggregateId: id ?? _id(2),
      sequence: 1,
      status: LocalMutationStatus.pending,
      createdAtUtc: DateTime.utc(2026),
      operation: operation,
      baseVersion: 0,
      body: body,
    );

    test('references are read from every body that carries them', () {
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('workout', {
            'sourcePlanId': _id(10),
            'sourceWorkoutId': _id(11),
            'exercises': [
              {'sourceExerciseId': _id(12)},
            ],
          }),
        ),
        {_id(10), _id(11), _id(12)},
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('training-plan', {
            'entries': [
              {'exerciseId': _id(12)},
            ],
          }),
        ),
        {_id(12)},
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('training-plan', {
            'plans': [
              {'planId': _id(13)},
            ],
          }, operation: LocalMutationOperation.reorder),
        ),
        {_id(13)},
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('custom-exercise', {
            'categoryIds': [_id(14)],
            'targetExerciseId': _id(15),
          }),
        ),
        {_id(14), _id(15)},
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('training-schedule', {
            'slots': [
              {'planId': _id(16)},
              {'planId': null},
              {'planId': _id(2)},
            ],
            'exceptions': [
              {'date': '2026-10-22', 'planId': _id(17), 'movedToDate': null},
            ],
          }),
        ),
        {_id(16), _id(17)},
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(
          mutationOf('daily-check-in', {'weightKg': 80}),
        ),
        isEmpty,
      );
      expect(
        SyncPayloadCodec.referencedAggregateIds(mutationOf('workout', null)),
        isEmpty,
      );
    });
  });
}
