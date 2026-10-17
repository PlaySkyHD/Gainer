import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'component_harness.dart';

void main() {
  group('GainerNumericAccessoryBar', () {
    testWidgets('ruft die Callbacks auf und trägt Semantik-Labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final calls = <String>[];
      await tester.pumpWidget(
        componentHarness(
          child: GainerNumericAccessoryBar(
            onPrevious: () => calls.add('zurück'),
            onNext: () => calls.add('weiter'),
            onDone: () => calls.add('fertig'),
            onHideKeyboard: () => calls.add('ausblenden'),
          ),
        ),
      );

      for (final label in [
        'Zurück',
        'Weiter',
        'Fertig',
        'Tastatur ausblenden',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.tap(find.bySemanticsLabel('Weiter'));
      await tester.tap(find.bySemanticsLabel('Fertig'));
      await tester.tap(find.bySemanticsLabel('Tastatur ausblenden'));
      expect(calls, ['zurück', 'weiter', 'fertig', 'ausblenden']);
      semantics.dispose();
    });

    testWidgets('deaktiviert Buttons ohne Callback', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        componentHarness(child: const GainerNumericAccessoryBar(onNext: null)),
      );

      final next = tester.getSemantics(find.bySemanticsLabel('Weiter'));
      expect(next.flagsCollection.isEnabled, Tristate.isFalse);
      final previous = tester.getSemantics(find.bySemanticsLabel('Zurück'));
      expect(previous.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });
  });

  testWidgets('GainerSegmentedControl wechselt die Auswahl', (tester) async {
    final selections = <int>[];
    var value = 0;
    await tester.pumpWidget(
      componentHarness(
        child: StatefulBuilder(
          builder: (context, setState) => GainerSegmentedControl<int>(
            options: const {0: 'Tagebuch', 1: 'Pläne', 2: 'Statistik'},
            value: value,
            onChanged: (selected) {
              selections.add(selected);
              setState(() => value = selected);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pläne'));
    await tester.pumpAndSettle();
    expect(value, 1);

    await tester.tap(find.text('Statistik'));
    await tester.pumpAndSettle();
    expect(value, 2);
    expect(selections, [1, 2]);
  });

  testWidgets(
    'Toolbar-Buttons tragen Semantik-Labels und sind ohne Callback deaktiviert',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        componentHarness(
          child: Row(
            children: [
              GainerToolbarButton(
                icon: CupertinoIcons.add,
                semanticLabel: 'Hinzufügen',
                onPressed: () => taps++,
              ),
              const GainerToolbarButton(
                icon: CupertinoIcons.ellipsis,
                semanticLabel: 'Mehr',
                onPressed: null,
              ),
            ],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Hinzufügen'), findsOneWidget);
      expect(find.bySemanticsLabel('Mehr'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Mehr'))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      await tester.tap(find.bySemanticsLabel('Hinzufügen'));
      expect(taps, 1);
      semantics.dispose();
    },
  );
}
