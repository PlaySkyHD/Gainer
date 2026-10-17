import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_input.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/domain/models/training/workout_rules.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_view_model.dart';

import 'training_test_support.dart';

const _benchId = 'bench-source';
const _pullId = 'pull-source';

class _StaticCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async => const BaseCatalog(
    exercises: [
      CatalogExercise(
        id: _benchId,
        name: 'Bankdrücken',
        exerciseType: ExerciseKind.strength,
        notes: 'Griff schulterbreit',
        isBase: true,
      ),
      CatalogExercise(
        id: _pullId,
        name: 'Klimmzug',
        exerciseType: ExerciseKind.bodyweightLoaded,
        isBase: true,
      ),
    ],
    categories: [],
  );
}

WorkoutBlock _block(
  String id,
  String sourceId,
  String name,
  ExerciseKind kind,
  List<LoggedSet> sets, {
  String? supersetId,
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: sourceId,
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: kind,
  supersetId: supersetId,
  sets: sets,
);

void main() {
  late TrainingHarness harness;
  late TrainingLogRepository repository;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    harness = await TrainingHarness.create();
    var id = 1000;
    repository = TrainingLogRepository(
      store: harness.store,
      catalog: _StaticCatalog(),
      ids: () => testId(id++),
      clock: () => harness.now,
    );
    activeWorkout = ActiveWorkoutController(repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<WorkoutViewModel> openModel(String workoutId) async {
    final model = WorkoutViewModel(
      repository: repository,
      activeWorkout: activeWorkout,
      workoutId: workoutId,
    );
    addTearDown(model.dispose);
    await model.load();
    return model;
  }

  test(
    'gültiger Satzwert wird gespeichert und überlebt einen Neustart',
    () async {
      final workout = await harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
        blocks: [
          _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 's1'),
          ]),
        ],
      );
      final model = await openModel(workout.workoutId);

      await model.setWeight('b1', 's1', 102.5);
      await model.setRepetitions('b1', 's1', 8);

      // Ein neues Repository auf derselben Datenbank entspricht einem Neustart.
      final restarted = TrainingLogRepository(
        store: harness.store,
        catalog: _StaticCatalog(),
        clock: () => harness.now,
      );
      final stored = await restarted.readWorkout(workout.workoutId);
      final set = stored!.exercises.single.sets.single;
      expect(set.weightKg, 102.5);
      expect(set.repetitions, 8);
      expect(isBlockComplete(stored.exercises.single), isTrue);
    },
  );

  test('Änderung ohne Wertunterschied erzeugt keine Speicherung', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 80, repetitions: 5),
        ]),
      ],
    );
    final model = await openModel(workout.workoutId);
    await model.setWeight('b1', 's1', 80);
    expect(model.hasUnsavedChanges, isFalse);
  });

  test(
    'Vorwerte stammen aus früheren Trainings und werden nicht gespeichert',
    () async {
      await harness.seedWorkout(
        title: 'Push A',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _block('old', _benchId, 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
            const LoggedSet(setId: 'o2', weightKg: 100, repetitions: 7),
          ]),
        ],
      );
      final current = await harness.seedWorkout(
        title: 'Push B',
        start: DateTime.utc(2026, 10, 16, 8),
        blocks: [
          _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 's1'),
            const LoggedSet(setId: 's2'),
          ]),
        ],
      );
      final model = await openModel(current.workoutId);

      final previous = model.previousValues['b1']!;
      expect(previous[0]?.weightKg, 100);
      expect(previous[0]?.repetitions, 8);
      expect(previous[1]?.repetitions, 7);
      expect(model.workout!.exercises.single.sets.first.weightKg, isNull);
      expect(isBlockComplete(model.workout!.exercises.single), isFalse);
    },
  );

  test('ohne frühere Einheit gibt es keine Vorwerte', () async {
    final current = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 16, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    final model = await openModel(current.workoutId);

    expect(model.previousValues['b1']!.single, isNull);
  });

  test('Vorwert übernehmen füllt nur leere Felder', () async {
    await harness.seedWorkout(
      title: 'Push A',
      start: DateTime.utc(2026, 10, 10, 8),
      end: DateTime.utc(2026, 10, 10, 9),
      blocks: [
        _block('old', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
        ]),
      ],
    );
    final current = await harness.seedWorkout(
      title: 'Push B',
      start: DateTime.utc(2026, 10, 16, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', repetitions: 6),
        ]),
      ],
    );
    final model = await openModel(current.workoutId);

    await model.applyPreviousValues('b1', 's1');

    final set = model.workout!.exercises.single.sets.single;
    expect(set.weightKg, 100);
    expect(set.repetitions, 6);
  });

  test('Verlauf zeigt neueste Einheit zuerst und nur erfasste Sätze', () async {
    await harness.seedWorkout(
      title: 'Alt',
      start: DateTime.utc(2026, 10, 1, 8),
      end: DateTime.utc(2026, 10, 1, 9),
      blocks: [
        _block('a', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 'a1', weightKg: 60, repetitions: 10),
        ]),
      ],
    );
    await harness.seedWorkout(
      title: 'Neu',
      start: DateTime.utc(2026, 10, 9, 8),
      end: DateTime.utc(2026, 10, 9, 9),
      blocks: [
        _block('n', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 'n1'),
          const LoggedSet(setId: 'n2', weightKg: 70, repetitions: 5),
        ]),
      ],
    );
    final current = await harness.seedWorkout(
      title: 'Heute',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    final model = await openModel(current.workoutId);

    final history = model.historyFor(model.workout!.exercises.single);

    expect(history.map((entry) => entry.workout.title), ['Neu', 'Alt']);
    expect(history.first.sets.map((set) => set.setId), ['n2']);
    expect(history.last.sets.single.weightKg, 60);
  });

  test('Satz duplizieren, entfernen und verschieben', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 50, repetitions: 10),
          const LoggedSet(setId: 's2', setType: SetType.warmup),
        ]),
      ],
    );
    final model = await openModel(workout.workoutId);

    await model.duplicateSet('b1', 's1');
    var sets = model.workout!.exercises.single.sets;
    expect(sets, hasLength(3));
    expect(sets[1].setId, isNot('s1'));
    expect(sets[1].weightKg, 50);
    expect(sets[1].repetitions, 10);

    await model.moveSet('b1', sets[1].setId, 1);
    sets = model.workout!.exercises.single.sets;
    expect(sets.last.weightKg, 50);

    for (final set in List.of(model.workout!.exercises.single.sets)) {
      await model.removeSet('b1', set.setId);
    }
    expect(model.workout!.exercises.single.sets, isEmpty);
    expect(model.workout!.exercises.single.workoutExerciseId, 'b1');
  });

  test('neuer Satz übernimmt den Typ des letzten Satzes', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', setType: SetType.dropset),
        ]),
      ],
    );
    final model = await openModel(workout.workoutId);

    await model.addSet('b1');

    final sets = model.workout!.exercises.single.sets;
    expect(sets.last.setType, SetType.dropset);
    expect(sets.last.weightKg, isNull);
  });

  test('Blocknotiz ändert nicht die Stammnotiz der Übung', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    final model = await openModel(workout.workoutId);
    final block = model.workout!.exercises.single;

    await model.setBlockNotes('b1', 'Schulter zwickt');

    expect(model.workout!.exercises.single.notes, 'Schulter zwickt');
    expect(model.exerciseNoteFor(block), 'Griff schulterbreit');
    final catalog = await repository.readExercises(includeArchived: true);
    expect(
      catalog.firstWhere((e) => e.id == _benchId).notes,
      'Griff schulterbreit',
    );
  });

  test('Superset verbinden und lösen', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [
        _block('b1', _benchId, 'Bankdrücken', ExerciseKind.strength, const []),
        _block(
          'b2',
          _pullId,
          'Klimmzug',
          ExerciseKind.bodyweightLoaded,
          const [],
        ),
      ],
    );
    final model = await openModel(workout.workoutId);

    await model.connectWithNextBlock('b1');
    final blocks = model.workout!.exercises;
    expect(blocks[0].supersetId, isNotNull);
    expect(blocks[1].supersetId, blocks[0].supersetId);

    await model.detachFromSuperset('b2');
    expect(model.workout!.exercises[1].supersetId, isNull);
    expect(model.workout!.exercises[0].supersetId, isNotNull);
  });

  test(
    'Metadaten: Titel, Notiz und gültige Zeiten werden gespeichert',
    () async {
      final workout = await harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 15, 18),
        end: DateTime.utc(2026, 10, 15, 19),
      );
      final model = await openModel(workout.workoutId);

      await model.setTitle('  Legs 2  ');
      await model.setNotes('Gut gelaufen');
      await model.setEndedAt(DateTime.utc(2026, 10, 15, 19, 30));
      await model.setStartedAt(DateTime.utc(2026, 10, 15, 17, 45));

      final stored = await repository.readWorkout(workout.workoutId);
      expect(stored!.title, 'Legs 2');
      expect(stored.notes, 'Gut gelaufen');
      expect(stored.startedAtUtc, DateTime.utc(2026, 10, 15, 17, 45));
      expect(stored.endedAtUtc, DateTime.utc(2026, 10, 15, 19, 30));
    },
  );

  test(
    'ungültige Endzeit und leerer Titel lassen den Stand unverändert',
    () async {
      final workout = await harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 15, 18),
        end: DateTime.utc(2026, 10, 15, 19),
      );
      final model = await openModel(workout.workoutId);

      expect(
        model.validateEndedAt(DateTime.utc(2026, 10, 15, 17, 30)),
        isNotNull,
      );
      await model.setEndedAt(DateTime.utc(2026, 10, 15, 17, 30));
      await model.setStartedAt(DateTime.utc(2026, 10, 15, 19, 30));
      await model.setTitle('   ');

      expect(model.hasUnsavedChanges, isFalse);
      final stored = await repository.readWorkout(workout.workoutId);
      expect(stored!.title, 'Push');
      expect(stored.startedAtUtc, DateTime.utc(2026, 10, 15, 18));
      expect(stored.endedAtUtc, DateTime.utc(2026, 10, 15, 19));
    },
  );

  test('Einstellungen bleiben kontogebunden erhalten', () async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
    );
    final model = await openModel(workout.workoutId);
    expect(model.showRir, isFalse);
    expect(model.weightUnit, WeightUnit.kg);

    await model.setShowRir(true);
    await model.setWeightUnit(WeightUnit.lbs);

    final reopened = await openModel(workout.workoutId);
    expect(reopened.showRir, isTrue);
    expect(reopened.weightUnit, WeightUnit.lbs);
    final raw = await TrainingPreferences(store: harness.store).read();
    expect(
      raw,
      const TrainingPreferenceValues(showRir: true, weightUnit: WeightUnit.lbs),
    );
  });
}
