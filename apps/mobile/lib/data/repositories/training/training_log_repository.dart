import '../../../domain/models/body/body_tracking.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/previous_values.dart' as previous;
import '../../../domain/models/training/training_plan_model.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart' as rules;
import '../../../domain/models/training/workout_validation.dart';
import '../../models/local/local_aggregate.dart';
import '../../models/local/local_mutation.dart';
import '../sync/local_sync_store.dart';
import 'api_exercise_catalog_provider.dart';
import 'muscle_suggestion_service.dart';
import 'training_preferences.dart';
import 'training_schedule_repository.dart';

const _workoutType = 'workout';
const _planType = 'training-plan';
const _customExerciseType = 'custom-exercise';
const _categoryType = 'exercise-category';
const _checkInType = 'daily-check-in';

/// Ein zweites aktives Training ist nicht erlaubt. Die UI kann das laufende
/// Training anbieten, statt ein neues zu starten.
class ActiveWorkoutExistsException implements Exception {
  const ActiveWorkoutExistsException(this.workoutId);

  final String workoutId;

  @override
  String toString() => 'ActiveWorkoutExistsException($workoutId)';
}

/// Schreibt und liest Training, Pläne, Rhythmus und Übungskatalog des
/// angemeldeten Kontos. Jede bestätigte Änderung landet atomar im lokalen Store
/// zusammen mit ihrer Outbox-Mutation; schlägt das fehl, wirft die Methode.
class TrainingLogRepository {
  TrainingLogRepository({
    required this.store,
    required this.catalog,
    IdFactory? ids,
    DateTime Function()? clock,
    this.muscleSuggestions,
  }) : _ids = ids ?? newUuidV4,
       _clock = clock ?? DateTime.now;

  final LocalSyncStore store;
  final ExerciseCatalogProvider catalog;

  /// KI für Muskeln einer Übung; ohne Wert bietet die App sie nicht an.
  final MuscleSuggestionService? muscleSuggestions;

  /// Trainingseinstellungen des Kontos; ein gemeinsamer Stand für alle Beobachter.
  late final TrainingPreferences preferences = TrainingPreferences(
    store: store,
  );

  /// Trainingsrhythmus mit Vorschau und Tagesaktionen.
  late final TrainingScheduleRepository schedule = TrainingScheduleRepository(
    store: store,
    ids: _ids,
    clock: _clock,
    readAllPlans: () => readPlans(includeArchived: true),
    readWorkouts: readDiary,
  );
  final IdFactory _ids;
  final DateTime Function() _clock;

  /// Liefert eine neue ID für Trainings, Sätze, Pläne und Übungen.
  String newId() => _ids();

  /// Aktuelle Zeit der Repository-Uhr in UTC, z. B. für Zeiträume.
  DateTime nowUtc() => _clock().toUtc();

  /// True, wenn der Katalog aus dem Cache stammt.
  bool get isCatalogStale => catalog.lastLoadWasStale;

  // Lesen

  Future<List<Workout>> _allWorkouts() async => [
    for (final row in await store.readAggregates(_workoutType))
      Workout.fromJson(_asMap(row.workingCopy)),
  ];

  Future<Workout?> readActiveWorkout() async =>
      _firstOrNull((await _allWorkouts()).where((w) => w.isActive));

  /// Alle nicht gelöschten Trainings, neueste zuerst.
  Future<List<Workout>> readDiary() async {
    final workouts = (await _allWorkouts())
        .where((w) => w.deletedAtUtc == null)
        .toList();
    workouts.sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
    return workouts;
  }

  Future<Workout?> readWorkout(String workoutId) async {
    final row = await store.readAggregate(_workoutType, workoutId);
    if (row == null) return null;
    final workout = Workout.fromJson(_asMap(row.workingCopy));
    return workout.deletedAtUtc == null ? workout : null;
  }

  /// Pläne nach Reihenfolge. Archivierte Pläne nur mit [includeArchived].
  Future<List<TrainingPlanModel>> readPlans({
    bool includeArchived = false,
  }) async {
    final plans = await _allPlans();
    final visible = plans
        .where((plan) => includeArchived || !plan.isArchived)
        .toList();
    visible.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return visible;
  }

  Future<TrainingPlanModel?> readPlan(String planId) async {
    final row = await store.readAggregate(_planType, planId);
    return row == null ? null : _planOf(row);
  }

  /// Übungen für Auswahl und Anzeige: Basiskatalog und eigene Übungen.
  Future<List<CatalogExercise>> readExercises({
    bool includeArchived = false,
  }) async {
    final base = await catalog.loadBaseCatalog();
    final own = [
      for (final row in await store.readAggregates(_customExerciseType))
        CatalogExercise.fromJson(_asMap(row.workingCopy)),
    ];
    final all = [
      ...base.exercises,
      ...own,
    ].where((exercise) => includeArchived || !exercise.isArchived).toList();
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  /// Nur die eigenen Übungen aus dem lokalen Store, ohne den Basiskatalog
  /// (der ihn über das Netz lädt). Für Kennzahlen, die offline entstehen.
  Future<List<CatalogExercise>> readOwnExercises() async => [
    for (final row in await store.readAggregates(_customExerciseType))
      CatalogExercise.fromJson(_asMap(row.workingCopy)),
  ];

  /// Kategorien: Basiskategorien und eigene Kategorien.
  Future<List<CatalogCategory>> readCategories({
    bool includeArchived = false,
  }) async {
    final base = await catalog.loadBaseCatalog();
    final own = [
      for (final row in await store.readAggregates(_categoryType))
        CatalogCategory.fromJson(_asMap(row.workingCopy)),
    ];
    final all = [
      ...base.categories,
      ...own,
    ].where((category) => includeArchived || !category.isArchived).toList();
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  /// Lokale Check-ins, die für die Statistik zu einem Training gehören.
  Future<List<DailyCheckIn>> readCheckIns() async => [
    for (final row in await store.readAggregates(_checkInType))
      DailyCheckIn.fromJson(_asMap(row.workingCopy)),
  ];

  // Trainings

  /// Startet ein leeres Training. Ein zweites aktives Training wird abgelehnt.
  Future<Workout> startEmpty({String title = 'Training'}) =>
      _serialStart(() async {
        await _requireNoActiveWorkout();
        return _createWorkout(rules.emptyWorkout(_ids, _clock(), title));
      });

  Future<Workout> startFromPlan(String planId) => _serialStart(() async {
    await _requireNoActiveWorkout();
    final plan = await readPlan(planId);
    if (plan == null || plan.isArchived) {
      throw StateError('Der Plan ist nicht verfügbar.');
    }
    final workout = rules.workoutFromPlan(
      plan,
      await readExercises(includeArchived: true),
      _ids,
      _clock(),
    );
    return _createWorkout(workout);
  });

  /// Wiederholt ein beendetes Training. Die Vorwertquelle bestimmt der Aufrufer.
  Future<Workout> startRepeat(
    String sourceWorkoutId, {
    required PreviousValueSource previousValueSource,
  }) => _serialStart(() async {
    await _requireNoActiveWorkout();
    final source = await readWorkout(sourceWorkoutId);
    if (source == null) throw StateError('Das Training ist nicht verfügbar.');
    return _createWorkout(
      rules.workoutFromRepeat(source, _ids, _clock(), previousValueSource),
    );
  });

  /// Starts laufen nacheinander: Prüfen auf ein aktives Training und Anlegen
  /// sind getrennte Schritte. Ohne Reihenfolge legten zwei schnelle Starts
  /// (Doppeltipp) zwei aktive Trainings an, die der Server dann ablehnt.
  Future<Workout> _serialStart(Future<Workout> Function() start) {
    // Ohne laufenden Start sofort in der Zone des Aufrufers starten; eine
    // vorab angelegte Kette liefe sonst in fremder Zone (z. B. im Widget-Test
    // mit simulierter Uhr nie).
    final previous = _startQueue;
    final result = previous == null
        ? Future.sync(start)
        : previous.then((_) => start());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _startQueue = tail;
    tail.whenComplete(() {
      if (identical(_startQueue, tail)) _startQueue = null;
    });
    return result;
  }

  /// Ende des zuletzt begonnenen Starts; null, wenn keiner läuft.
  Future<void>? _startQueue;

  /// Speichert eine geänderte Fassung des Trainings. Jede Feldänderung ist
  /// ein Aufruf; aufeinanderfolgende ungesendete Änderungen werden gebündelt.
  Future<Workout> saveWorkout(Workout workout) async {
    final old = await _requireEnvelope(_workoutType, workout.workoutId);
    final current = Workout.fromJson(_asMap(old.workingCopy));
    if (current.deletedAtUtc != null) {
      throw StateError('Das Training wurde gelöscht.');
    }
    if (workout.isActive && !current.isActive) {
      await _requireNoActiveWorkout(exceptId: workout.workoutId);
    }
    validateWorkout(workout);
    final body = workout.toJson();
    await _commit(
      aggregateType: _workoutType,
      aggregateId: workout.workoutId,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(workout.workoutId, old, body),
    );
    return workout;
  }

  /// Beendet das Training mit der aktuellen Zeit. Mit [applyPreviousValues]
  /// werden leere Gewichts- und Wiederholungsfelder aus dem Vorwert gefüllt.
  Future<Workout> finishWorkout(
    String workoutId, {
    bool applyPreviousValues = false,
  }) async {
    var workout = await _requireActiveWorkout(workoutId);
    if (applyPreviousValues) {
      final history = [
        for (final candidate in await readDiary())
          if (candidate.workoutId != workoutId) candidate,
      ];
      workout = previous.applyPreviousValues(
        workout,
        previous.previousValuesFor(workout, history),
      );
    }
    workout = workout.copyWith(endedAtUtc: () => _roundToSecond(_clock()));
    return saveWorkout(workout);
  }

  /// Setzt ein beendetes Training wieder auf aktiv.
  Future<Workout> resumeWorkout(String workoutId) async {
    final workout = await readWorkout(workoutId);
    if (workout == null || workout.endedAtUtc == null) {
      throw StateError('Das Training ist nicht beendet.');
    }
    return saveWorkout(workout.copyWith(endedAtUtc: () => null));
  }

  /// Löscht ein Training lokal sofort aus dem Tagebuch; der Server folgt über Sync.
  Future<void> deleteWorkout(String workoutId) async {
    final old = await _requireEnvelope(_workoutType, workoutId);
    final current = Workout.fromJson(_asMap(old.workingCopy));
    if (current.deletedAtUtc != null) return;
    final body = current
        .copyWith(deletedAtUtc: () => _roundToSecond(_clock()))
        .toJson();
    await _commit(
      aggregateType: _workoutType,
      aggregateId: workoutId,
      operation: LocalMutationOperation.delete,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(workoutId, old, body),
    );
  }

  // Pläne

  Future<TrainingPlanModel> createPlan(TrainingPlanModel draft) async {
    validateTrainingPlan(draft);
    final plans = await _allPlans();
    final plan = draft.copyWith(
      sortOrder: _nextSortOrder(plans),
      isArchived: false,
    );
    await _commit(
      aggregateType: _planType,
      aggregateId: plan.planId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: plan.toJson(),
      envelope: localEnvelope(
        aggregateId: plan.planId,
        workingCopy: plan.toJson(),
      ),
    );
    return plan;
  }

  Future<TrainingPlanModel> updatePlan(TrainingPlanModel plan) async {
    final old = await _requireEnvelope(_planType, plan.planId);
    final current = _planOf(old);
    if (current.isArchived) throw StateError('Der Plan ist archiviert.');
    validateTrainingPlan(plan);
    final next = plan.copyWith(sortOrder: current.sortOrder, isArchived: false);
    await _commit(
      aggregateType: _planType,
      aggregateId: plan.planId,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: next.toJson(),
      envelope: _pending(plan.planId, old, next.toJson()),
    );
    return next;
  }

  Future<void> archivePlan(String planId) async {
    final old = await _requireEnvelope(_planType, planId);
    final current = _planOf(old);
    if (current.isArchived) return;
    final body = current.copyWith(isArchived: true).toJson();
    await _commit(
      aggregateType: _planType,
      aggregateId: planId,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(planId, old, body),
    );
  }

  /// Ordnet alle aktiven Pläne neu. Die Liste muss alle aktiven Pläne genau
  /// einmal enthalten. Die Umsortierung ist eine einzige Mutation und setzt
  /// voraus, dass alle betroffenen Pläne synchronisiert sind.
  Future<void> reorderPlans(List<String> planIdsInOrder) async {
    final active = await readPlans();
    final activeIds = {for (final plan in active) plan.planId};
    if (planIdsInOrder.length != active.length ||
        planIdsInOrder.toSet().length != planIdsInOrder.length ||
        !planIdsInOrder.every(activeIds.contains)) {
      throw const WorkoutValidationException({
        'planIds':
            'Die Reihenfolge muss alle aktiven Pläne genau einmal enthalten.',
      });
    }
    final envelopes = <String, LocalAggregateEnvelope<Object?>>{};
    for (final planId in planIdsInOrder) {
      final envelope = await _requireEnvelope(_planType, planId);
      if (envelope.serverVersion == null ||
          envelope.syncState != LocalSyncState.clean) {
        throw StateError(
          'Warte auf die Synchronisierung, bevor du die Reihenfolge änderst.',
        );
      }
      envelopes[planId] = envelope;
    }

    final bodies = <String, Map<String, Object?>>{
      for (var i = 0; i < planIdsInOrder.length; i++)
        planIdsInOrder[i]: _planOf(envelopes[planIdsInOrder[i]]!)
            .copyWith(sortOrder: i)
            .toJson(),
    };
    final first = planIdsInOrder.first;
    await _commit(
      aggregateType: _planType,
      aggregateId: first,
      operation: LocalMutationOperation.reorder,
      baseVersion: envelopes[first]!.serverVersion,
      body: {
        'plans': [
          for (final planId in planIdsInOrder)
            {'planId': planId, 'baseVersion': envelopes[planId]!.serverVersion},
        ],
      },
      envelope: _pending(first, envelopes[first]!, bodies[first]!),
      related: [
        for (final planId in planIdsInOrder.skip(1))
          (_planType, _pending(planId, envelopes[planId]!, bodies[planId]!)),
      ],
    );
  }

  /// Vorschlag für ein Training als Plan. Ein gleichnamiger aktiver Plan wird
  /// dabei erkannt; die UI fragt dann, ob er überschrieben werden soll.
  Future<rules.PlanFromWorkout> previewPlanFromWorkout(String workoutId) async {
    final workout = await _requireWorkoutForPlan(workoutId);
    return rules.planFromWorkout(workout, await _allPlans(), _ids);
  }

  /// Speichert ein Training als Plan. Mit [overwriteExisting] ersetzt der
  /// Plan den gleichnamigen aktiven Plan, sonst entsteht ein neuer.
  Future<TrainingPlanModel> saveWorkoutAsPlan(
    String workoutId, {
    bool overwriteExisting = false,
  }) async {
    final preview = await previewPlanFromWorkout(workoutId);
    final existing = preview.existingPlan;
    if (existing != null && overwriteExisting) {
      return updatePlan(preview.plan.copyWith(planId: existing.planId));
    }
    return createPlan(preview.plan);
  }

  // Katalog

  Future<CatalogExercise> createCustomExercise(CatalogExercise draft) async {
    if (draft.isBase) throw StateError('Basisübungen sind nicht änderbar.');
    validateCatalogExercise(draft);
    await _requireActiveCategories(draft.categoryIds);
    final exercise = draft.copyWith(isArchived: false);
    await _commit(
      aggregateType: _customExerciseType,
      aggregateId: exercise.id,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: exercise.toJson(),
      envelope: localEnvelope(
        aggregateId: exercise.id,
        workingCopy: exercise.toJson(),
      ),
    );
    return exercise;
  }

  Future<CatalogExercise> updateCustomExercise(CatalogExercise exercise) async {
    final old = await _requireOwnExercise(exercise.id);
    validateCatalogExercise(exercise);
    await _requireActiveCategories(exercise.categoryIds);
    final next = exercise.copyWith(isArchived: false);
    await _commit(
      aggregateType: _customExerciseType,
      aggregateId: exercise.id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: next.toJson(),
      envelope: _pending(exercise.id, old, next.toJson()),
    );
    return next;
  }

  Future<void> archiveCustomExercise(String exerciseId) async {
    final old = await _requireOwnExercise(exerciseId);
    final current = CatalogExercise.fromJson(_asMap(old.workingCopy));
    if (current.isArchived) return;
    final body = current.copyWith(isArchived: true).toJson();
    await _commit(
      aggregateType: _customExerciseType,
      aggregateId: exerciseId,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(exerciseId, old, body),
    );
  }

  Future<CatalogCategory> createCategory(CatalogCategory draft) async {
    if (draft.isBase) throw StateError('Basiskategorien sind nicht änderbar.');
    validateCatalogCategory(draft);
    final category = draft.copyWith(isArchived: false);
    await _commit(
      aggregateType: _categoryType,
      aggregateId: category.id,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: category.toJson(),
      envelope: localEnvelope(
        aggregateId: category.id,
        workingCopy: category.toJson(),
      ),
    );
    return category;
  }

  Future<CatalogCategory> updateCategory(CatalogCategory category) async {
    final old = await _requireOwnCategory(category.id);
    validateCatalogCategory(category);
    final next = category.copyWith(isArchived: false, isBase: false);
    await _commit(
      aggregateType: _categoryType,
      aggregateId: category.id,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: next.toJson(),
      envelope: _pending(category.id, old, next.toJson()),
    );
    return next;
  }

  Future<void> archiveCategory(String categoryId) async {
    final old = await _requireOwnCategory(categoryId);
    final current = CatalogCategory.fromJson(_asMap(old.workingCopy));
    if (current.isArchived) return;
    final body = current.copyWith(isArchived: true).toJson();
    await _commit(
      aggregateType: _categoryType,
      aggregateId: categoryId,
      operation: LocalMutationOperation.update,
      baseVersion: old.serverVersion,
      body: body,
      envelope: _pending(categoryId, old, body),
    );
  }

  /// Führt eine eigene Übung in eine andere (Basis- oder eigene) Übung zusammen.
  /// Lokal werden Referenzen in eigenen Trainings und Plänen auf das Ziel
  /// umgeschrieben und die Quelle archiviert. Namens-Snapshots bleiben
  /// unverändert. Der Server führt die Zusammenführung endgültig aus.
  Future<void> mergeExercises({
    required String sourceExerciseId,
    required String targetExerciseId,
  }) async {
    if (sourceExerciseId == targetExerciseId) {
      throw StateError('Quelle und Ziel müssen verschieden sein.');
    }
    final source = await _requireOwnExercise(sourceExerciseId);
    final sourceExercise = _requireMergeableSource(source);
    if (!(await readExercises()).any((item) => item.id == targetExerciseId)) {
      throw StateError('Das Ziel ist nicht verfügbar.');
    }
    final targetRow = await store.readAggregate(
      _customExerciseType,
      targetExerciseId,
    );

    final related = [
      ...await _workoutsReferencingExercise(sourceExerciseId, targetExerciseId),
      ...await _plansReferencingExercise(sourceExerciseId, targetExerciseId),
    ];

    final archivedSource = sourceExercise.copyWith(isArchived: true).toJson();
    await _commit(
      aggregateType: _customExerciseType,
      aggregateId: sourceExerciseId,
      operation: LocalMutationOperation.merge,
      baseVersion: source.serverVersion,
      body: {
        ...archivedSource,
        'targetExerciseId': targetExerciseId,
        'targetBaseVersion': targetRow?.serverVersion,
      },
      envelope: _pending(sourceExerciseId, source, archivedSource),
      related: related,
    );
  }

  // Interna

  CatalogExercise _requireMergeableSource(
    LocalAggregateEnvelope<Object?> source,
  ) {
    if (source.serverVersion == null ||
        source.syncState != LocalSyncState.clean) {
      throw StateError(
        'Warte auf die Synchronisierung, bevor du zusammenführst.',
      );
    }
    final sourceExercise = CatalogExercise.fromJson(_asMap(source.workingCopy));
    if (sourceExercise.isArchived) {
      throw StateError('Die Quelle ist bereits archiviert.');
    }
    return sourceExercise;
  }

  Future<List<(String, LocalAggregateEnvelope<Object?>)>>
  _workoutsReferencingExercise(
    String sourceExerciseId,
    String targetExerciseId,
  ) async {
    final related = <(String, LocalAggregateEnvelope<Object?>)>[];
    for (final workout in await _allWorkouts()) {
      if (workout.deletedAtUtc != null ||
          !workout.exercises.any(
            (block) => block.sourceExerciseId == sourceExerciseId,
          )) {
        continue;
      }
      final rewritten = workout.copyWith(
        exercises: [
          for (final block in workout.exercises)
            block.sourceExerciseId == sourceExerciseId
                ? block.copyWith(sourceExerciseId: targetExerciseId)
                : block,
        ],
      );
      final row = await store.readAggregate(_workoutType, workout.workoutId);
      related.add((
        _workoutType,
        _pending(workout.workoutId, row!, rewritten.toJson()),
      ));
    }
    return related;
  }

  Future<List<(String, LocalAggregateEnvelope<Object?>)>>
  _plansReferencingExercise(
    String sourceExerciseId,
    String targetExerciseId,
  ) async {
    final related = <(String, LocalAggregateEnvelope<Object?>)>[];
    for (final plan in await _allPlans()) {
      if (!plan.entries.any((entry) => entry.exerciseId == sourceExerciseId)) {
        continue;
      }
      final rewritten = plan.copyWith(
        entries: [
          for (final entry in plan.entries)
            entry.exerciseId == sourceExerciseId
                ? entry.copyWith(exerciseId: targetExerciseId)
                : entry,
        ],
      );
      final row = await store.readAggregate(_planType, plan.planId);
      related.add((_planType, _pending(plan.planId, row!, rewritten.toJson())));
    }
    return related;
  }

  Future<List<TrainingPlanModel>> _allPlans() async => [
    for (final row in await store.readAggregates(_planType)) _planOf(row),
  ];

  TrainingPlanModel _planOf(LocalAggregateEnvelope<Object?> row) =>
      TrainingPlanModel.fromJson(_asMap(row.workingCopy));

  int _nextSortOrder(List<TrainingPlanModel> plans) {
    var next = 0;
    for (final plan in plans) {
      if (plan.sortOrder >= next) next = plan.sortOrder + 1;
    }
    return next;
  }

  Future<Workout> _createWorkout(Workout workout) async {
    validateWorkout(workout);
    final body = workout.toJson();
    await _commit(
      aggregateType: _workoutType,
      aggregateId: workout.workoutId,
      operation: LocalMutationOperation.create,
      baseVersion: 0,
      body: body,
      envelope: localEnvelope(
        aggregateId: workout.workoutId,
        workingCopy: body,
      ),
    );
    return workout;
  }

  Future<void> _requireNoActiveWorkout({String? exceptId}) async {
    final active = await readActiveWorkout();
    if (active != null && active.workoutId != exceptId) {
      throw ActiveWorkoutExistsException(active.workoutId);
    }
  }

  Future<Workout> _requireActiveWorkout(String workoutId) async {
    final workout = await readWorkout(workoutId);
    if (workout == null || !workout.isActive) {
      throw StateError('Das Training ist nicht aktiv.');
    }
    return workout;
  }

  Future<Workout> _requireWorkoutForPlan(String workoutId) async {
    final workout = await readWorkout(workoutId);
    if (workout == null) throw StateError('Das Training ist nicht verfügbar.');
    return workout;
  }

  Future<LocalAggregateEnvelope<Object?>> _requireEnvelope(
    String aggregateType,
    String aggregateId,
  ) async {
    final row = await store.readAggregate(aggregateType, aggregateId);
    if (row == null) throw StateError('Der Eintrag ist nicht verfügbar.');
    return row;
  }

  Future<LocalAggregateEnvelope<Object?>> _requireOwnExercise(
    String exerciseId,
  ) async {
    final row = await _requireEnvelope(_customExerciseType, exerciseId);
    if (CatalogExercise.fromJson(_asMap(row.workingCopy)).isBase) {
      throw StateError('Basisübungen sind nicht änderbar.');
    }
    return row;
  }

  Future<LocalAggregateEnvelope<Object?>> _requireOwnCategory(
    String categoryId,
  ) async {
    final row = await _requireEnvelope(_categoryType, categoryId);
    if (CatalogCategory.fromJson(_asMap(row.workingCopy)).isBase) {
      throw StateError('Basiskategorien sind nicht änderbar.');
    }
    return row;
  }

  Future<void> _requireActiveCategories(List<String> categoryIds) async {
    if (categoryIds.isEmpty) return;
    final available = {
      for (final category in await readCategories()) category.id,
    };
    if (!categoryIds.every(available.contains)) {
      throw const WorkoutValidationException({
        'categoryIds': 'Eine Kategorie ist nicht verfügbar.',
      });
    }
  }

  LocalAggregateEnvelope<Object?> _pending(
    String aggregateId,
    LocalAggregateEnvelope<Object?> old,
    Map<String, Object?> body,
  ) => LocalAggregateEnvelope<Object?>(
    aggregateId: aggregateId,
    serverSnapshot: old.serverSnapshot,
    workingCopy: body,
    serverVersion: old.serverVersion,
    optimisticVersion: old.optimisticVersion + 1,
    syncState: LocalSyncState.pending,
  );

  Future<void> _commit({
    required String aggregateType,
    required String aggregateId,
    required LocalMutationOperation operation,
    required int? baseVersion,
    required Map<String, Object?> body,
    required LocalAggregateEnvelope<Object?> envelope,
    List<(String, LocalAggregateEnvelope<Object?>)> related = const [],
  }) async {
    await store.commitMutation(
      mutationId: _ids(),
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      operation: operation,
      baseVersion: baseVersion,
      body: body,
      envelope: envelope,
      relatedEnvelopes: related,
      createdAtUtc: _clock().toUtc(),
    );
  }
}

Map<String, Object?> _asMap(Object? value) => value! as Map<String, Object?>;

T? _firstOrNull<T>(Iterable<T> values) {
  for (final value in values) {
    return value;
  }
  return null;
}

/// Sekundengenau in UTC, damit die Endzeit in JSON und Sync stabil ist.
DateTime _roundToSecond(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}
