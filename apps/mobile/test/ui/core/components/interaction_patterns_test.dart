import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'component_harness.dart';

Future<void> _pumpOpener(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) open,
  List<Object?> results,
) async {
  await tester.pumpWidget(
    componentHarness(
      child: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () => open(context).then(results.add),
          child: const Text('Öffnen'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
}

Future<Object?> _openSheet(BuildContext context) => showGainerSheet<String>(
  context: context,
  builder: (sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GainerSheetHeader(
        title: 'Mahlzeit',
        trailing: GainerPillButton(
          label: 'Speichern',
          onPressed: () => Navigator.of(sheetContext).pop('saved'),
        ),
      ),
      const SizedBox(height: 200, child: Center(child: Text('Inhalt'))),
    ],
  ),
);

void main() {
  group('showGainerSheet', () {
    testWidgets('kurzes Ziehen federt zurück, schnelles Wischen schließt', (
      tester,
    ) async {
      final results = <Object?>[];
      await _pumpOpener(tester, _openSheet, results);
      expect(find.text('Mahlzeit'), findsOneWidget);
      expect(find.byType(GainerSheetGrabber), findsOneWidget);

      await tester.timedDrag(
        find.text('Inhalt'),
        const Offset(0, 30),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mahlzeit'), findsOneWidget);

      await tester.fling(find.text('Inhalt'), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Mahlzeit'), findsNothing);
      expect(results, [null]);
    });

    testWidgets('X schließt ohne Ergebnis, Aktion liefert Ergebnis', (
      tester,
    ) async {
      final results = <Object?>[];
      await _pumpOpener(tester, _openSheet, results);
      await tester.tap(find.bySemanticsLabel('Schließen'));
      await tester.pumpAndSettle();
      expect(results, [null]);

      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(results, [null, 'saved']);
    });
  });

  group('GainerSwipeToDelete', () {
    Future<List<String>> pumpRow(WidgetTester tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(
        componentHarness(
          child: Builder(
            builder: (context) => GainerSwipeToDelete(
              dismissKey: const ValueKey('row'),
              confirm: () => confirmGainerDelete(
                context,
                title: 'Eintrag löschen?',
                message: 'Haferflocken wird entfernt.',
              ),
              onDeleted: () => deleted.add('row'),
              child: const SizedBox(
                height: 60,
                width: 300,
                child: Text('Haferflocken'),
              ),
            ),
          ),
        ),
      );
      return deleted;
    }

    testWidgets('Abbrechen lässt die Zeile stehen', (tester) async {
      final deleted = await pumpRow(tester);
      await tester.drag(find.text('Haferflocken'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Eintrag löschen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(find.text('Haferflocken'), findsOneWidget);
    });

    testWidgets('Bestätigen löscht', (tester) async {
      final deleted = await pumpRow(tester);
      await tester.drag(find.text('Haferflocken'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen').last);
      await tester.pumpAndSettle();
      expect(deleted, ['row']);
    });

    testWidgets('Minus-Button meldet den Tipp', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        componentHarness(
          child: GainerDeleteMinusButton(
            semanticLabel: 'Haferflocken löschen',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Haferflocken löschen'));
      expect(taps, 1);
    });
  });

  group('GainerDateRow', () {
    testWidgets('zeigt den Wert und übernimmt die Auswahl mit Fertig', (
      tester,
    ) async {
      final picked = <DateTime>[];
      final value = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        componentHarness(
          child: GainerDateRow(
            title: 'Von',
            value: value,
            format: (date) => '${date.day}.${date.month}.${date.year}',
            onChanged: picked.add,
          ),
        ),
      );
      expect(find.text('12.10.2026'), findsOneWidget);

      await tester.tap(find.text('Von'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(picked, [value]);
    });

    testWidgets('Abbruch ändert nichts', (tester) async {
      final picked = <DateTime>[];
      await tester.pumpWidget(
        componentHarness(
          child: GainerDateRow(
            title: 'Bis',
            value: DateTime(2026, 10, 18),
            format: (date) => '${date.day}.${date.month}.',
            onChanged: picked.add,
          ),
        ),
      );
      await tester.tap(find.text('Bis'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Schließen'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });
  });

  testWidgets('GainerSectionHeader zeigt Titel und Zusatz', (tester) async {
    await tester.pumpWidget(
      componentHarness(
        child: const GainerSectionHeader(title: 'Mahlzeiten', trailing: '3'),
      ),
    );
    expect(find.text('Mahlzeiten'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
