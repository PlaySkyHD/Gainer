import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_preferences.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';

const _account = '00000000-0000-4000-8000-0000000000a1';

void main() {
  test('zwei schnelle Änderungen verwerfen sich nicht gegenseitig', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = CardioPreferences(
      store: LocalSyncStore(database: database, accountId: _account),
    );

    await Future.wait([
      preferences.update((values) => values.copyWith(warmupSeconds: 240)),
      preferences.update((values) => values.copyWith(alertsEnabled: false)),
    ]);

    final stored = await preferences.read();
    expect(stored.warmupSeconds, 240);
    expect(stored.alertsEnabled, isFalse);
  });
}
