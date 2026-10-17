import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

import 'component_harness.dart';

const _sheetActions = [
  GainerSheetAction<String>(
    label: 'Verschieben',
    icon: CupertinoIcons.arrow_up_arrow_down,
    value: 'move',
  ),
  GainerSheetAction<String>(
    label: 'Löschen',
    icon: CupertinoIcons.trash,
    value: 'delete',
    destructive: true,
  ),
];

/// Öffnet ein Sheet über einen Button; jedes Ergebnis (auch null) landet in `results`.
Future<void> _openSheet(WidgetTester tester, List<Object?> results) async {
  await tester.pumpWidget(
    componentHarness(
      child: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () => showGainerActionSheet<String>(
            context: context,
            title: 'Bankdrücken',
            quickActions: _sheetActions,
          ).then(results.add),
          child: const Text('Öffnen'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
  expect(find.text('Bankdrücken'), findsOneWidget);
}

void main() {
  group('GainerActionSheet', () {
    testWidgets('schließt per X ohne Ergebnis', (tester) async {
      final results = <Object?>[];
      await _openSheet(tester, results);

      await tester.tap(find.bySemanticsLabel('Schließen'));
      await tester.pumpAndSettle();

      expect(results, [null]);
      expect(find.text('Bankdrücken'), findsNothing);
    });

    testWidgets('schließt per Wischen nach unten ohne Ergebnis', (
      tester,
    ) async {
      final results = <Object?>[];
      await _openSheet(tester, results);

      await tester.fling(find.text('Bankdrücken'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();

      expect(results, [null]);
      expect(find.text('Bankdrücken'), findsNothing);
    });

    testWidgets('liefert die gewählte Aktion', (tester) async {
      final results = <Object?>[];
      await _openSheet(tester, results);

      await tester.tap(find.text('Verschieben'));
      await tester.pumpAndSettle();

      expect(results, ['move']);
    });

    testWidgets('zeigt destruktive Aktion in Rolle destructive', (
      tester,
    ) async {
      final results = <Object?>[];
      await _openSheet(tester, results);

      final label = tester.widget<Text>(find.text('Löschen'));
      expect(label.style?.color, GainerColors.light.destructive);
    });
  });

  group('GainerStackedDialog', () {
    Future<void> openDialog(WidgetTester tester, List<Object?> results) async {
      await tester.pumpWidget(
        componentHarness(
          child: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => showGainerStackedDialog<String>(
                context: context,
                title: 'Training löschen?',
                message: 'Dieser Vorgang kann nicht rückgängig gemacht werden.',
                actions: const [
                  GainerDialogAction(label: 'Abbrechen', value: 'cancel'),
                  GainerDialogAction(
                    label: 'Löschen',
                    value: 'delete',
                    destructive: true,
                  ),
                ],
              ).then(results.add),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Training löschen?'), findsOneWidget);
    }

    testWidgets('liefert die gewählte Aktion', (tester) async {
      final results = <Object?>[];
      await openDialog(tester, results);

      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();

      expect(results, ['delete']);
    });

    testWidgets('hat keine Standardaktion: Return bestätigt nichts', (
      tester,
    ) async {
      final results = <Object?>[];
      await openDialog(tester, results);

      await pressReturn(tester);
      await tester.pumpAndSettle();

      expect(results, isEmpty);
      expect(find.text('Training löschen?'), findsOneWidget);
    });

    testWidgets('destruktive Aktion ist rot beschriftet', (tester) async {
      final results = <Object?>[];
      await openDialog(tester, results);

      final label = tester.widget<Text>(find.text('Löschen'));
      expect(label.style?.color, GainerColors.light.destructive);
    });
  });
}
