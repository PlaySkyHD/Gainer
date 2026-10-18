import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/sync/sync_status.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

import '../../../../integration_test/ui_design_fixture.dart'
    show createUiDesignFixture;

void main() {
  // Ohne und mit Hinweis „Dieses iPhone lädt nichts hoch“.
  for (final writer in [true, false]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final name = writer ? 'more_screen' : 'more_screen_banner';
      testWidgets(
        'more menu${writer ? '' : ' with sync banner'} matches golden in ${brightness.name} mode',
        (tester) async {
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
            fixture.app(GainerTheme.forBrightness(brightness)),
          );
          await tester.pumpAndSettle();
          (fixture.account.syncStatus as ValueNotifier<SyncStatus>).value =
              SyncStatus(
                // Das Alter bleibt knapp über zwei Minuten, damit die Fußnote
                // „vor 2 Min.“ lautet, auch wenn der Test etwas länger läuft.
                lastSyncedAtUtc: DateTime.now().subtract(
                  const Duration(minutes: 2, seconds: 10),
                ),
                pendingCount: 3,
                isWriter: writer,
              );
          await tester.tap(find.text('Mehr').last);
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(CupertinoApp),
            matchesGoldenFile('goldens/${name}_${brightness.name}.png'),
          );
          expect(tester.takeException(), isNull);
        },
        tags: ['golden'],
      );
    }
  }
}
