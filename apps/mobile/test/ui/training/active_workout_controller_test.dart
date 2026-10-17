import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';

import 'training_test_support.dart';

/// Repository, dessen Lesen des aktiven Trainings sich gezielt fehlschlagen lässt.
class _ReadFailingRepository extends TrainingLogRepository {
  _ReadFailingRepository({required super.store, required super.catalog});

  bool failReads = false;

  @override
  Future<Workout?> readActiveWorkout() async {
    if (failReads) throw StateError('Lesen fehlgeschlagen.');
    return super.readActiveWorkout();
  }
}

void main() {
  late TrainingHarness harness;
  late _ReadFailingRepository repository;
  late ActiveWorkoutController controller;

  setUp(() async {
    harness = await TrainingHarness.create();
    repository = _ReadFailingRepository(
      store: harness.store,
      catalog: harness.repository.catalog,
    );
    controller = ActiveWorkoutController(repository);
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  test('Lesefehler lassen den letzten bekannten Stand stehen', () async {
    await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
    );
    await controller.load();
    expect(controller.active?.title, 'Push');

    repository.failReads = true;
    await expectLater(controller.load(), completes);

    expect(controller.active?.title, 'Push');
    expect(controller.lastLoadError, isA<StateError>());

    repository.failReads = false;
    await controller.load();
    expect(controller.lastLoadError, isNull);
    expect(controller.active?.title, 'Push');
  });
}
