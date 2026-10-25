import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const _accountId = '00000000-0000-4000-8000-000000000093';
const _day = '2026-10-25';

/// Liest den Tag sofort, gibt ihn aber erst frei, wenn [gate] es erlaubt.
/// So entsteht ein Laden, dessen Stand während des Wartens veraltet.
class _GatedRepository extends NutritionRepository {
  _GatedRepository({required super.store, required super.ids, super.clock});

  Completer<void>? gate;

  @override
  Future<NutritionSnapshot> read(String localDate) async {
    final snapshot = await super.read(localDate);
    final wait = gate;
    if (wait != null) await wait.future;
    return snapshot;
  }
}

void main() {
  test(
    'a reload never replaces a newer water total with an older one',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var next = 700;
      final repository = _GatedRepository(
        store: LocalSyncStore(database: database, accountId: _accountId),
        ids: () =>
            '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
        clock: () => DateTime.utc(2026, 10, 25, 9),
      );
      await repository.water.setAmount(_day, 500);
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: _day,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();
      expect(viewModel.waterMl, 500);

      repository.gate = Completer<void>();
      final reload = viewModel.load();
      // Das Laden hat 500 ml gelesen; jetzt tippt der Nutzer.
      await pumpEventQueue();
      expect(await viewModel.addWater(200), isTrue);
      expect(viewModel.waterMl, 700);

      repository.gate!.complete();
      await reload;

      expect(viewModel.waterMl, 700);
      expect(await repository.water.read(_day), 700);
    },
  );

  test('loading another day ignores water changes of the shown day', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var next = 800;
    final repository = _GatedRepository(
      store: LocalSyncStore(database: database, accountId: _accountId),
      ids: () =>
          '00000000-0000-4000-8000-${(++next).toString().padLeft(12, '0')}',
      clock: () => DateTime.utc(2026, 10, 25, 9),
    );
    await repository.water.setAmount('2026-10-24', 300);
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: _day,
    );
    addTearDown(viewModel.dispose);
    await viewModel.load();

    repository.gate = Completer<void>();
    final switchDay = viewModel.selectDate('2026-10-24');
    await pumpEventQueue();
    expect(await viewModel.addWater(200), isTrue);
    repository.gate!.complete();
    await switchDay;

    expect(viewModel.localDate, '2026-10-24');
    expect(viewModel.waterMl, 300);
    expect(await repository.water.read(_day), 200);
  });
}
