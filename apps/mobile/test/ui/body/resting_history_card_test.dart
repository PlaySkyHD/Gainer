import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/body/body_tracking.dart';
import 'package:gainer_mobile/ui/features/body/resting_history_card.dart';

import '../training/training_test_support.dart';

void main() {
  // 320 pt breit: „zuletzt …“ und die Legenden konkurrieren um die Breite.
  for (final scale in [1.3, 2.0]) {
    for (final pending in [false, true]) {
      testWidgets('Ruhewerte laufen bei Textgröße $scale nicht über '
          '(wartet auf Check-in: $pending)', (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          trainingTestApp(
            textScale: scale,
            home: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RestingHistoryCard(
                today: DateTime(2026, 10, 20),
                entries: [
                  const RestingEntry(
                    localDate: '2026-10-10',
                    restingHeartRateBpm: 61,
                    restingHrvMs: 44,
                  ),
                  RestingEntry(
                    localDate: '2026-10-20',
                    restingHeartRateBpm: 57,
                    restingHrvMs: 55,
                    isPending: pending,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('HRV 55 ms'), findsOneWidget);
        expect(find.text('Ruhepuls 57 bpm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
