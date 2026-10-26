import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/training_home_view_model.dart';

import 'training_test_support.dart';

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;
  late TrainingHomeViewModel viewModel;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
    viewModel = TrainingHomeViewModel(
      repository: harness.repository,
      activeWorkout: activeWorkout,
      cardio: CardioRepository(store: harness.store),
    );
  });

  tearDown(() async {
    viewModel.dispose();
    activeWorkout.dispose();
    await harness.dispose();
  });

  test(
    'fehlgeschlagenes Löschen eines Trainings bleibt als Meldung stehen',
    () async {
      await harness.seedWorkout(
        title: 'Legs',
        start: DateTime(2026, 10, 15, 18).toUtc(),
        end: DateTime(2026, 10, 15, 19).toUtc(),
      );
      await viewModel.loadDiary();

      // Eine unbekannte ID lässt das Speichern der Löschung scheitern.
      await viewModel.deleteWorkout('unbekannt');

      expect(
        viewModel.errorMessage,
        'Das Training konnte nicht gelöscht werden.',
      );
      expect(viewModel.diary, hasLength(1));
    },
  );

  test(
    'fehlgeschlagenes Löschen einer Cardio-Einheit bleibt als Meldung stehen',
    () async {
      await viewModel.loadDiary();

      await viewModel.deleteCardio('unbekannt');

      expect(
        viewModel.errorMessage,
        'Die Cardio-Einheit konnte nicht gelöscht werden.',
      );
    },
  );
}
