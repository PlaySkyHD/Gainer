import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'component_harness.dart';

void main() {
  testWidgets('Ladezustand deaktiviert den Button und zeigt einen Spinner', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      componentHarness(
        child: GainerPillButton(
          label: 'Speichern',
          isLoading: true,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Speichern, lädt'), findsOneWidget);
    await tester.tap(find.byType(CupertinoButton), warnIfMissed: false);
    expect(taps, 0);
    semantics.dispose();
  });

  testWidgets('Ladezustand behält die Größe des Buttons', (tester) async {
    Future<Size> sizeOf({required bool loading}) async {
      await tester.pumpWidget(
        componentHarness(
          child: GainerPillButton(
            label: 'Speichern',
            icon: CupertinoIcons.checkmark,
            isLoading: loading,
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(CupertinoButton));
    }

    final idle = await sizeOf(loading: false);
    final loading = await sizeOf(loading: true);
    expect(loading, idle);
  });

  testWidgets('Icon steht vor dem Label', (tester) async {
    await tester.pumpWidget(
      componentHarness(
        child: const GainerPillButton(
          label: 'Hinzufügen',
          icon: CupertinoIcons.add,
          onPressed: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = tester.getCenter(find.byIcon(CupertinoIcons.add));
    final text = tester.getCenter(find.text('Hinzufügen'));
    expect(icon.dx, lessThan(text.dx));
  });

  testWidgets('Untertitel und trailing erscheinen in der Zeile', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      componentHarness(
        child: GainerListRow(
          title: 'Konto',
          subtitle: 'Aktiv',
          leadingIcon: CupertinoIcons.person_2,
          leadingIconBackground: const Color(0xFF34C759),
          trailing: CupertinoSwitch(
            value: toggled,
            onChanged: (value) => toggled = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Konto'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.person_2), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
  });

  testWidgets('langer Wert bleibt auf 60 Prozent begrenzt', (tester) async {
    const long =
        'Ein sehr langer Wert, der umbrechen muss statt die Zeile zu sprengen';
    await tester.pumpWidget(
      componentHarness(
        child: const GainerListRow(title: 'Titel', value: long),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final rowWidth = tester.getSize(find.byType(GainerListRow)).width;
    expect(
      tester.getSize(find.text(long)).width,
      lessThanOrEqualTo(rowWidth * 0.6),
    );
  });
}
