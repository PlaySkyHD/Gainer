import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/workout_view_model.dart';

import 'training_test_support.dart';

/// Repository, dessen Speichern sich für Tests gezielt fehlschlagen lässt.
class _FlakyRepository extends TrainingLogRepository {
  _FlakyRepository({required super.store, required super.catalog, super.clock});

  bool failSaves = false;

  @override
  Future<Workout> saveWorkout(Workout workout) async {
    if (failSaves) throw StateError('Speicher nicht verfügbar.');
    return super.saveWorkout(workout);
  }
}

void main() {
  late TrainingHarness harness;
  late _FlakyRepository repository;
  late ActiveWorkoutController activeWorkout;
  late String workoutId;

  setUp(() async {
    harness = await TrainingHarness.create();
    repository = _FlakyRepository(
      store: harness.store,
      catalog: harness.repository.catalog,
      clock: () => harness.now,
    );
    activeWorkout = ActiveWorkoutController(repository);
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: [strengthBlock('Bankdrücken', 2, id: 'bench')],
    );
    workoutId = workout.workoutId;
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  WorkoutViewModel viewModel() => WorkoutViewModel(
    repository: repository,
    activeWorkout: activeWorkout,
    workoutId: workoutId,
  );

  test('Änderungen werden gespeichert', () async {
    final model = viewModel();
    addTearDown(model.dispose);
    await model.load();

    await model.edit((w) => w.copyWith(title: 'Push B'));

    expect(model.errorMessage, isNull);
    expect(model.hasUnsavedChanges, isFalse);
    final stored = await repository.readWorkout(workoutId);
    expect(stored?.title, 'Push B');
  });

  test('Fehler melden und Änderung ohne Datenverlust halten', () async {
    final model = viewModel();
    addTearDown(model.dispose);
    await model.load();

    repository.failSaves = true;
    await model.edit((w) => w.copyWith(title: 'Push B'));

    expect(model.errorMessage, isNotNull);
    expect(model.hasUnsavedChanges, isTrue);
    expect(model.workout?.title, 'Push B');
    expect((await repository.readWorkout(workoutId))?.title, 'Push');

    repository.failSaves = false;
    await model.retrySave();

    expect(model.errorMessage, isNull);
    expect(model.hasUnsavedChanges, isFalse);
    expect((await repository.readWorkout(workoutId))?.title, 'Push B');
  });

  test('Beenden speichert offene Änderungen und endet das Training', () async {
    final model = viewModel();
    addTearDown(model.dispose);
    await model.load();
    await model.edit((w) => w.copyWith(title: 'Push C'));

    harness.now = DateTime.utc(2026, 10, 17, 9);
    final outcome = await model.requestFinish();

    expect(outcome, WorkoutFinishOutcome.finished);
    final stored = await repository.readWorkout(workoutId);
    expect(stored?.title, 'Push C');
    expect(stored?.endedAtUtc, DateTime.utc(2026, 10, 17, 9));
    expect(activeWorkout.hasActiveWorkout, isFalse);
  });

  group('Aufwärmhinweis', () {
    const previous = [LoggedSet(setId: 'p1', weightKg: 40, repetitions: 8)];

    WorkoutBlock block(ExerciseKind kind) => WorkoutBlock(
      workoutExerciseId: 'we-$kind',
      sourceExerciseId: 'src-$kind',
      exerciseNameSnapshot: 'Übung',
      exerciseTypeSnapshot: kind,
      sets: const [LoggedSet(setId: 's1')],
    );

    test('erscheint bei Kraftübungen mit Vorwert', () async {
      final model = viewModel();
      addTearDown(model.dispose);
      await model.load();

      final hint = model.warmupHintFor(block(ExerciseKind.strength), previous);

      expect(hint?.map((t) => t.weightKg), [20, 32.5]);
    });

    test('fehlt bei assistierten Übungen', () async {
      final model = viewModel();
      addTearDown(model.dispose);
      await model.load();

      expect(
        model.warmupHintFor(block(ExerciseKind.assisted), previous),
        isNull,
      );
    });
  });
}
