import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/repositories/training/training_preferences.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _accountA = '00000000-0000-4000-8000-0000000000a1';
const _accountB = '00000000-0000-4000-8000-0000000000b1';

void main() {
  test('Detailfreigabe ist standardmäßig an und meldet Änderungen', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final preferences = TrainingPreferences(
      store: LocalSyncStore(database: database, accountId: _accountA),
    );
    addTearDown(database.close);

    expect((await preferences.read()).liveActivityDetails, isTrue);
    expect(preferences.liveActivityDetails.value, isTrue);

    await preferences.write(
      const TrainingPreferenceValues(liveActivityDetails: false),
    );

    expect(preferences.liveActivityDetails.value, isFalse);
    expect((await preferences.read()).liveActivityDetails, isFalse);
  });

  test('zwei schnelle Änderungen verwerfen sich nicht gegenseitig', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = TrainingPreferences(
      store: LocalSyncStore(database: database, accountId: _accountA),
    );

    await Future.wait([
      preferences.update((values) => values.copyWith(showRir: true)),
      preferences.update((values) => values.copyWith(autoStartRestTimer: true)),
    ]);

    final stored = await preferences.read();
    expect(stored.showRir, isTrue);
    expect(stored.autoStartRestTimer, isTrue);
  });

  test('ein gespeichertes Aus bleibt aus, auch mit neuem Standard', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await TrainingPreferences(
      store: LocalSyncStore(database: database, accountId: _accountA),
    ).write(const TrainingPreferenceValues(liveActivityDetails: false));

    final preferences = TrainingPreferences(
      store: LocalSyncStore(database: database, accountId: _accountA),
    );

    expect((await preferences.read()).liveActivityDetails, isFalse);
    expect(preferences.liveActivityDetails.value, isFalse);
  });

  test('Detailfreigabe bleibt nach einem Neustart erhalten', () async {
    final directory = Directory.systemTemp.createTempSync('gainer-prefs-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/account.sqlite');

    final first = LocalDatabase(NativeDatabase(file));
    await TrainingPreferences(
      store: LocalSyncStore(database: first, accountId: _accountA),
    ).write(const TrainingPreferenceValues(liveActivityDetails: true));
    await first.close();

    final restarted = LocalDatabase(NativeDatabase(file));
    addTearDown(restarted.close);
    final preferences = TrainingPreferences(
      store: LocalSyncStore(database: restarted, accountId: _accountA),
    );

    expect((await preferences.read()).liveActivityDetails, isTrue);
    expect(preferences.liveActivityDetails.value, isTrue);
  });

  test('Detailfreigabe gehört nur zu dem Konto, das sie gesetzt hat', () async {
    final accountA = LocalDatabase(NativeDatabase.memory());
    final accountB = LocalDatabase(NativeDatabase.memory());
    addTearDown(accountA.close);
    addTearDown(accountB.close);

    await TrainingPreferences(
      store: LocalSyncStore(database: accountA, accountId: _accountA),
    ).write(const TrainingPreferenceValues(liveActivityDetails: false));

    final other = TrainingPreferences(
      store: LocalSyncStore(database: accountB, accountId: _accountB),
    );
    expect((await other.read()).liveActivityDetails, isTrue);
    expect(other.liveActivityDetails.value, isTrue);
  });
}
