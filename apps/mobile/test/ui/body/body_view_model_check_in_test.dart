import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';

const _account = '00000000-0000-4000-8000-000000000001';

void main() {
  late LocalDatabase database;
  late BodyRepository repository;
  late BodyViewModel model;
  final now = DateTime.utc(2026, 10, 24, 12);
  var id = 10;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    repository = BodyRepository(
      store: LocalSyncStore(database: database, accountId: _account),
      ids: () =>
          '00000000-0000-4000-8000-${(id++).toString().padLeft(12, '0')}',
      clock: () => now,
    );
    model = BodyViewModel(repository);
  });

  tearDown(() async {
    model.dispose();
    await database.close();
  });

  Future<void> storeFullCheckIn() => repository.saveCheckIn(
    localDate: '2026-10-24',
    weightKg: 82,
    caloriesKcal: 2400,
    proteinGrams: 150,
    carbohydrateGrams: 260,
    fatGrams: 80,
    steps: 9000,
    sleepMinutes: 450,
  );

  test('saving without a loaded snapshot keeps calories and sleep', () async {
    await storeFullCheckIn();
    expect(model.snapshot, isNull);

    await model.saveCheckIn(localDate: '2026-10-24', weightKg: 81.5);

    final saved = (await repository.read()).checkIns.single.value;
    expect(saved.weightKg, 81.5);
    expect(saved.caloriesKcal, 2400);
    expect(saved.proteinGrams, 150);
    expect(saved.carbohydrateGrams, 260);
    expect(saved.fatGrams, 80);
    expect(saved.steps, 9000);
    expect(saved.sleepMinutes, 450);
  });

  test('steps read by the editor never lower a newer stored total', () async {
    await storeFullCheckIn();
    // Der Editor liest 9000, danach speichert HealthStepsSync 12000.
    const readByEditor = 9000;
    await repository.updateSteps(localDate: '2026-10-24', steps: 12000);

    await repository.saveCheckIn(
      localDate: '2026-10-24',
      weightKg: 81.5,
      steps: readByEditor,
    );

    final saved = (await repository.read()).checkIns.single.value;
    expect(saved.steps, 12000);
    expect(saved.caloriesKcal, 2400);
    expect(saved.sleepMinutes, 450);
  });

  test('a check-in changed after loading is not overwritten by the old '
      'snapshot', () async {
    await storeFullCheckIn();
    await model.load();
    // Danach ändert ein Sync oder HealthStepsSync den Check-in.
    await repository.updateSteps(localDate: '2026-10-24', steps: 12000);

    await model.saveCheckIn(
      localDate: '2026-10-24',
      weightKg: 81.5,
      sleepMinutes: 480,
    );

    final saved = (await repository.read()).checkIns.single.value;
    expect(saved.steps, 12000);
    expect(saved.caloriesKcal, 2400);
    expect(saved.sleepMinutes, 480);
  });
}
