import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000004';

void main() {
  testWidgets('manual diary entry is persisted as one local sync mutation', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database: database, accountId: accountId);
    final repository = NutritionRepository(
      store: store,
      ids: () => '00000000-0000-4000-8000-000000000005',
      clock: () => DateTime.utc(2026, 10, 12, 10),
    );
    final viewModel = NutritionViewModel(
      repository: repository,
      localDate: '2026-10-12',
    );
    await tester.pumpWidget(
      MaterialApp(home: NutritionScreen(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Haferflocken');
    await tester.enterText(find.byType(TextField).at(2), '60');
    await tester.enterText(find.byType(TextField).at(3), '370');
    await tester.ensureVisible(find.text('Manuell speichern'));
    await tester.tap(find.text('Manuell speichern'));
    await tester.pumpAndSettle();

    expect(viewModel.snapshot!.day.entries.single.productName, 'Haferflocken');
    expect(
      await store.readOutbox(aggregateType: 'nutrition-day'),
      hasLength(1),
    );
    expect(viewModel.statusMessage, contains('lokal gespeichert'));
  });
}
