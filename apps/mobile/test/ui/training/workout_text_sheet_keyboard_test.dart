import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/workout_text_sheet.dart';

import '../core/components/component_harness.dart';

void main() {
  testWidgets('Umbenennen-Feld bleibt über der Tastatur', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      componentHarness(
        child: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showWorkoutTextSheet(
              context: context,
              title: 'Titel',
              initialText: 'Push',
            ),
            child: const Text('Umbenennen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Umbenennen'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(CupertinoTextField));
    expect(field.bottom, lessThanOrEqualTo(844 - 336));
  });
}
