import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

/// Die Tagespfeile in der linken Toolbar-Position bleiben antippbar, egal wie
/// breit die rechten Aktionen sind. Früher lag die rechte Gruppe über dem
/// rechten Pfeil, weil die linke Aktion beliebig breit werden konnte.
void main() {
  // „Mi. 30. Sept.“: eines der längsten Datumsformate der Pille.
  const label = 'Mi. 30. Sept.';

  final trailingVariants = <String, List<Widget> Function(VoidCallback)>{
    'two icons (nutrition)': (tap) => [
      GainerToolbarButton(
        key: const ValueKey('right-1'),
        icon: CupertinoIcons.add,
        semanticLabel: 'Hinzufügen',
        onPressed: tap,
      ),
      GainerToolbarButton(
        icon: CupertinoIcons.ellipsis,
        semanticLabel: 'Mehr',
        onPressed: () {},
      ),
    ],
    'one icon (calendar)': (tap) => [
      GainerToolbarButton(
        key: const ValueKey('right-1'),
        icon: CupertinoIcons.ellipsis,
        semanticLabel: 'Rhythmus',
        onPressed: tap,
      ),
    ],
    'text pill': (tap) => [
      GainerPillButton(
        key: const ValueKey('right-1'),
        label: 'Sichern',
        onPressed: tap,
      ),
    ],
    'toolbar group': (tap) => [
      GainerToolbarGroup(
        key: const ValueKey('right-1'),
        actions: [
          GainerToolbarAction(
            icon: CupertinoIcons.share,
            semanticLabel: 'Teilen',
            onPressed: tap,
          ),
          GainerToolbarAction(
            icon: CupertinoIcons.trash,
            semanticLabel: 'Löschen',
            onPressed: () {},
          ),
          GainerToolbarAction(
            icon: CupertinoIcons.ellipsis,
            semanticLabel: 'Mehr',
            onPressed: () {},
          ),
        ],
      ),
    ],
  };

  for (final MapEntry(key: name, value: buildTrailing)
      in trailingVariants.entries) {
    for (final width in [390.0, 320.0]) {
      for (final scale in [1.0, 2.0]) {
        // Die Testschrift ist breiter als die Systemschrift: Die Text-Pille
        // ließe bei 320 pt und Textgröße 2 dort keine 88 pt für die Pfeile.
        if (name == 'text pill' && width == 320 && scale == 2) continue;
        testWidgets('arrows and right action work: $name, ${width}pt, '
            'text scale $scale', (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var previous = 0;
          var next = 0;
          var right = 0;
          await tester.pumpWidget(
            CupertinoApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: GainerScaffold(
                title: 'Seite',
                leading: GainerDayNavigator(
                  pillKey: const ValueKey('pill'),
                  label: label,
                  onPrevious: () => previous++,
                  onNext: () => next++,
                  onPick: () {},
                ),
                trailing: buildTrailing(() => right++),
                children: const [SizedBox(height: 10)],
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Kein Überlauf, keine Assertion im Layout.
          expect(tester.takeException(), isNull);

          final prevArrow = find.byIcon(CupertinoIcons.chevron_left);
          final nextArrow = find.byIcon(CupertinoIcons.chevron_right);
          expect(prevArrow.hitTestable(), findsOneWidget);
          expect(nextArrow.hitTestable(), findsOneWidget);

          // Beide Pfeile haben mindestens 44 pt Tap-Fläche.
          for (final arrow in [prevArrow, nextArrow]) {
            final button = find.ancestor(
              of: arrow,
              matching: find.byType(CupertinoButton),
            );
            final size = tester.getSize(button);
            expect(size.width, greaterThanOrEqualTo(44));
            expect(size.height, greaterThanOrEqualTo(44));
          }

          // Die linke Aktion endet vor der rechten.
          expect(
            tester.getRect(find.byType(GainerDayNavigator)).right,
            lessThanOrEqualTo(
              tester.getRect(find.byKey(const ValueKey('right-1'))).left,
            ),
          );

          final rightAction = name == 'toolbar group'
              ? find.byIcon(CupertinoIcons.share)
              : find.byKey(const ValueKey('right-1'));
          await tester.tap(prevArrow);
          await tester.tap(nextArrow);
          await tester.tap(rightAction);
          await tester.pump();
          expect((previous, next, right), (1, 1, 1));
        });
      }
    }
  }

  testWidgets('semantics label names the date even when the text is cut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      CupertinoApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: GainerScaffold(
          title: 'Seite',
          leading: GainerDayNavigator(
            label: label,
            onPrevious: () {},
            onNext: () {},
            onPick: () {},
          ),
          trailing: [
            GainerToolbarButton(
              icon: CupertinoIcons.add,
              semanticLabel: 'Hinzufügen',
              onPressed: () {},
            ),
          ],
          children: const [SizedBox(height: 10)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('$label, Tag auswählen'), findsOneWidget);
    expect(find.bySemanticsLabel('Vorheriger Tag'), findsOneWidget);
    expect(find.bySemanticsLabel('Nächster Tag'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('without a bounded width the navigator shows the full date', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: GainerDayNavigator(
              label: label,
              onPrevious: () {},
              onNext: () {},
              onPick: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
    expect(
      find.byIcon(CupertinoIcons.chevron_left).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('with almost no room only the arrows remain', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: GainerDayNavigator(
              label: label,
              onPrevious: () {},
              onNext: () {},
              onPick: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(label), findsNothing);
    expect(
      find.byIcon(CupertinoIcons.chevron_left).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byIcon(CupertinoIcons.chevron_right).hitTestable(),
      findsOneWidget,
    );
  });
}
