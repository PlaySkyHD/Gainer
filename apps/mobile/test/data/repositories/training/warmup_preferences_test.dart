import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/training/warmup.dart';

const _accountA = '00000000-0000-4000-8000-0000000000a1';
const _accountB = '00000000-0000-4000-8000-0000000000b1';

TrainingPreferences _preferences(LocalDatabase database, String account) =>
    TrainingPreferences(
      store: LocalSyncStore(database: database, accountId: account),
    );

void main() {
  test('ohne gespeicherte Werte gelten die Aufwärm-Standards', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final values = await _preferences(database, _accountA).read();

    expect(values.warmup, const WarmupSettings());
    expect(values.warmupOverrides, isEmpty);
  });

  test(
    'globale Einstellungen und Übungsabweichungen bleiben erhalten',
    () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const override = ExerciseWarmupOverride(
        exerciseId: 'curl',
        enabled: false,
        rounding: 1,
      );
      await _preferences(database, _accountA).update(
        (v) => v.copyWith(
          warmup: const WarmupSettings(
            showRepetitions: true,
            steps: [WarmupStep(percent: 60, repetitions: 6)],
          ),
          warmupOverrides: {'curl': override},
        ),
      );

      final restored = await _preferences(database, _accountA).read();

      expect(restored.warmup.showRepetitions, isTrue);
      expect(restored.warmup.steps, const [
        WarmupStep(percent: 60, repetitions: 6),
      ]);
      expect(restored.warmupOverrides, {'curl': override});
    },
  );

  test('jedes Konto hat eine eigene Datenbank mit eigenen Werten', () async {
    final databaseA = LocalDatabase(NativeDatabase.memory());
    final databaseB = LocalDatabase(NativeDatabase.memory());
    addTearDown(databaseA.close);
    addTearDown(databaseB.close);
    await _preferences(
      databaseA,
      _accountA,
    ).update((v) => v.copyWith(warmup: const WarmupSettings(enabled: false)));

    expect(
      (await _preferences(databaseA, _accountA).read()).warmup.enabled,
      isFalse,
    );
    expect(
      (await _preferences(databaseB, _accountB).read()).warmup.enabled,
      isTrue,
    );
  });

  test('gleiche Werte sind gleich, andere Abweichungen nicht', () {
    const a = TrainingPreferenceValues(
      warmupOverrides: {
        'x': ExerciseWarmupOverride(exerciseId: 'x', rounding: 1),
      },
    );
    const b = TrainingPreferenceValues(
      warmupOverrides: {
        'x': ExerciseWarmupOverride(exerciseId: 'x', rounding: 1),
      },
    );
    const c = TrainingPreferenceValues(
      warmupOverrides: {
        'x': ExerciseWarmupOverride(exerciseId: 'x', rounding: 5),
      },
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
