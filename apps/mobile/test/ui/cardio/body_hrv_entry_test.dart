import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/ui/features/body/body_screen.dart';
import 'package:gainer_mobile/ui/features/body/body_view_model.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_feature.dart';
import 'package:gainer_mobile/ui/features/cardio/cardio_hrv_measurement_screen.dart';

import '../training/training_test_support.dart' hide testId;
import 'cardio_test_support.dart';

void main() {
  testWidgets('Körper-Tab führt zur HRV-Messung', (tester) async {
    phoneSize(tester, height: 1200);
    final harness = await tester.runAsync(CardioHarness.create);
    addTearDown(() => tester.runAsync(harness!.dispose));
    var id = 800;
    final body = BodyRepository(store: harness!.store, ids: () => testId(id++));
    final model = BodyViewModel(body);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      trainingTestApp(
        home: BodyScreen(
          viewModel: model,
          cardio: CardioFeature(
            repository: harness.repository,
            session: harness.controller,
            health: harness.feature.health,
            body: body,
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Ruhepuls und HRV'), findsOneWidget);
    expect(
      find.textContaining('Eine HRV-Messung mit Pulsgurt zeigt hier'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('body-open-hrv')));
    await settle(tester);
    expect(find.byType(HrvMeasurementScreen), findsOneWidget);
    expect(find.text('Messung starten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
