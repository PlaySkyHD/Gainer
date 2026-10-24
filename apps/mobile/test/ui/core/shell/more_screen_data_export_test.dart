import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/sync/data_export_screen.dart';

import '../../../../integration_test/ui_design_fixture.dart'
    show createUiDesignFixture;

void main() {
  testWidgets('„Daten exportieren“ unter Mehr öffnet den Export-Screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await tester.runAsync(createUiDesignFixture);
    if (fixture == null) {
      throw StateError('Could not create the design fixture.');
    }
    addTearDown(() => tester.runAsync(fixture.dispose));

    await tester.pumpWidget(
      fixture.app(GainerTheme.forBrightness(Brightness.light)),
    );
    await tester.pumpAndSettle();
    (fixture.account.syncStatus as ValueNotifier<SyncStatus>).value =
        const SyncStatus(pendingCount: 2);
    await tester.tap(find.text('Mehr').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-data-export')));
    await tester.pumpAndSettle();

    expect(find.byType(DataExportScreen), findsOneWidget);
    expect(
      find.textContaining('2 Änderungen sind noch nicht gesendet'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
