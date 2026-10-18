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

  testWidgets('GainerGroupedSection zeigt die Fußnote unter der Karte', (
    tester,
  ) async {
    await tester.pumpWidget(
      componentHarness(
        child: const GainerGroupedSection(
          header: 'Verbindung',
          footer: 'Änderungen werden mit deinem Konto abgeglichen.',
          children: [Text('Online')],
        ),
      ),
    );
    expect(
      find.text('Änderungen werden mit deinem Konto abgeglichen.'),
      findsOneWidget,
    );
  });

  testWidgets('GainerTextFieldRow zeigt Beschriftung, Einheit und Fehler', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(
      componentHarness(
        child: GainerTextFieldRow(
          label: 'Zielgewicht',
          unit: 'kg',
          placeholder: '0',
          errorText: 'Bitte eine Zahl eingeben.',
          fieldKey: const ValueKey('target'),
          onChanged: values.add,
        ),
      ),
    );
    expect(find.text('Zielgewicht'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('Bitte eine Zahl eingeben.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('target')), '76');
    expect(values, ['76']);
  });

  testWidgets('GainerScaffold aktualisiert beim Herunterziehen', (
    tester,
  ) async {
    var refreshed = 0;
    await tester.pumpWidget(
      componentHarness(
        child: GainerScaffold(
          title: 'Heute',
          onRefresh: () async => refreshed++,
          children: const [SizedBox(height: 2000, child: Text('Inhalt'))],
        ),
      ),
    );
    await tester.timedDrag(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Sheets bleiben mit offener Tastatur sichtbar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      componentHarness(
        child: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showGainerSheet<void>(
              context: context,
              builder: (_) =>
                  const CupertinoTextField(key: ValueKey('sheet-field')),
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byKey(const ValueKey('sheet-field')));
    expect(field.bottom, lessThanOrEqualTo(844 - 336));
  });

  testWidgets('Feste Sheet-Höhe schrumpft um die Tastatur', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    late double height;
    await tester.pumpWidget(
      componentHarness(
        child: Builder(
          builder: (context) {
            height = gainerSheetHeight(context, 0.9);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(height, closeTo(844 * 0.9 - 300, 0.01));
  });
}
