import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/ui/features/body/body_screen.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';

const accountId = '00000000-0000-4000-8000-000000000003';

void main() {
  testWidgets(
    'Body screen renders persisted active goal and validation errors',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = BodyRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
      );
      await repository.activateGoal(
        kind: BodyGoalKind.cut,
        startWeightKg: 82,
        targetWeightKg: 76,
        startDate: '2026-10-01',
        targetDate: null,
      );
      final model = BodyViewModel(repository);
      await tester.pumpWidget(CupertinoApp(home: BodyScreen(viewModel: model)));
      await tester.pumpAndSettle();

      expect(find.text('cut · 82.0 kg → 76.0 kg'), findsOneWidget);
      expect(find.byKey(const ValueKey('body-save-goal')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('body-save-checkin')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('body-save-checkin')));
      await tester.pumpAndSettle();
      expect(model.errorMessage, isNotNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('body-error')),
        -220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('body-error')), findsOneWidget);
    },
  );
}
