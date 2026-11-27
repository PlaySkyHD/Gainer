import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/sync/sync_screen.dart';

import '../../../../integration_test/ui_design_fixture.dart'
    show createUiDesignFixture;

void main() {
  testWidgets(
    '„Ansehen“ im Konflikthinweis öffnet „Sync & Gerät“ genau einmal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
          const SyncStatus(conflictCount: 1, writerKnown: true);
      await tester.pumpAndSettle();
      expect(find.text('1 Änderung nicht gespeichert'), findsOneWidget);

      await tester.tap(find.text('Ansehen'));
      await tester.pumpAndSettle();
      expect(find.byType(SyncScreen), findsOneWidget);

      // Die Seite liegt über allen Tabs; der Hinweis ist darunter verdeckt.
      expect(find.text('Ansehen').hitTestable(), findsNothing);

      // Der Weg über Mehr öffnet dieselbe Seite, ebenfalls nur einmal.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mehr').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync & Gerätewechsel'));
      await tester.pumpAndSettle();
      expect(find.byType(SyncScreen, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
