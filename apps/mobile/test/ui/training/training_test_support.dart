import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/api_exercise_catalog_provider.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

const trainingAccountId = '00000000-0000-4000-8000-000000000011';

String testId(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

class _NoCatalog implements ExerciseCatalogProvider {
  @override
  bool get lastLoadWasStale => false;

  @override
  Future<BaseCatalog> loadBaseCatalog() async =>
      const BaseCatalog(exercises: [], categories: []);
}

/// In-Memory-Datenbank mit Repository und steuerbarer Uhr.
class TrainingHarness {
  TrainingHarness._(this.database, this.store, this.repository, this._clock);

  final LocalDatabase database;
  final LocalSyncStore store;
  final TrainingLogRepository repository;
  final _Clock _clock;

  DateTime get now => _clock.value;

  set now(DateTime value) => _clock.value = value;

  static Future<TrainingHarness> create({DateTime? now}) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final store = LocalSyncStore(
      database: database,
      accountId: trainingAccountId,
    );
    final clock = _Clock(now ?? DateTime.utc(2026, 10, 17, 9));
    var id = 100;
    final repository = TrainingLogRepository(
      store: store,
      catalog: _NoCatalog(),
      ids: () => testId(id++),
      clock: () => clock.value,
    );
    return TrainingHarness._(database, store, repository, clock);
  }

  /// Legt ein Training an. Mit [end] wird es zu diesem Zeitpunkt beendet.
  Future<Workout> seedWorkout({
    required String title,
    required DateTime start,
    DateTime? end,
    List<WorkoutBlock> blocks = const [],
  }) async {
    now = start;
    var workout = await repository.startEmpty(title: title);
    if (blocks.isNotEmpty) {
      workout = await repository.saveWorkout(
        workout.copyWith(exercises: blocks),
      );
    }
    if (end != null) {
      now = end;
      workout = await repository.finishWorkout(workout.workoutId);
    }
    return workout;
  }

  Future<void> dispose() => database.close();
}

class _Clock {
  _Clock(this.value);
  DateTime value;
}

/// Satzblock mit gewichteten Sätzen für Tests des Tagebuchs.
WorkoutBlock strengthBlock(String name, int sets, {String id = 'block'}) =>
    WorkoutBlock(
      workoutExerciseId: '$id-$name',
      sourceExerciseId: '$id-source-$name',
      exerciseNameSnapshot: name,
      exerciseTypeSnapshot: ExerciseKind.strength,
      sets: [
        for (var i = 0; i < sets; i++)
          LoggedSet(setId: '$id-$name-set-$i', weightKg: 40, repetitions: 10),
      ],
    );

/// Lässt echte Datenbankantworten eintreffen und pumpt danach alle Frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Hülle für Widget-Tests mit Gainer-Farbrollen in der gewünschten Helligkeit.
Widget trainingTestApp({
  required Widget home,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: GainerTheme.forBrightness(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      platformBrightness: brightness,
      textScaler: TextScaler.linear(textScale),
    ),
    child: GainerDesign(child: child!),
  ),
  home: home,
);
