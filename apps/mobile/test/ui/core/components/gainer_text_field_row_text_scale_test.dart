import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'component_harness.dart';

/// Die Zeile stapelt die Beschriftung ab `> 1.5`: 1,3 liegt darunter, 1,5 genau
/// an der Schwelle (noch nebeneinander), 1,6 darüber.
const _scales = [1.3, 1.5, 1.6, 2.0];

void main() {
  for (final scale in _scales) {
    testWidgets('GainerTextFieldRow at 320 pt and text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        componentHarness(
          textScale: scale,
          child: SingleChildScrollView(
            child: Column(
              children: const [
                GainerTextFieldRow(
                  label: 'Gewicht pro Stück',
                  unit: 'kg',
                  placeholder: '0',
                  fieldKey: ValueKey('row-unit'),
                ),
                GainerTextFieldRow(
                  label: 'Name',
                  placeholder: 'Lebensmittel',
                  errorText: 'Bitte einen Namen eingeben.',
                  fieldKey: ValueKey('row-error'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in ['row-unit', 'row-error']) {
        final finder = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          finder,
          100,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(finder, findsOneWidget);
      }
      expect(find.text('kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
