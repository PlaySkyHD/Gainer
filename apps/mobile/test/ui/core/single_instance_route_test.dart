import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/navigation/single_instance_route.dart';

void main() {
  late BuildContext shellContext;

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
    CupertinoApp(
      home: Builder(
        builder: (context) {
          shellContext = context;
          return const Text('Shell');
        },
      ),
    ),
  );

  Future<void> open(WidgetTester tester, String key, String label) async {
    pushSingleInstance(
      shellContext,
      key: key,
      builder: (_) => CupertinoPageScaffold(child: Text(label)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('erneutes Öffnen holt den vorhandenen Screen nach vorn', (
    tester,
  ) async {
    await pumpShell(tester);
    await open(tester, 'workout:a', 'Leg (erste Instanz)');
    // Live Activity öffnet dasselbe Training noch einmal.
    await open(tester, 'workout:a', 'Leg (zweite Instanz)');

    expect(find.text('Leg (erste Instanz)'), findsOneWidget);
    expect(find.text('Leg (zweite Instanz)'), findsNothing);

    // Zurück führt zur Shell, nicht zu einer alten Kopie.
    Navigator.of(shellContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(find.text('Shell'), findsOneWidget);
    expect(find.textContaining('Leg'), findsNothing);
  });

  testWidgets('darüberliegende Screens werden geschlossen', (tester) async {
    await pumpShell(tester);
    await open(tester, 'workout:a', 'Leg');
    await open(tester, 'other', 'Übung');
    await open(tester, 'workout:a', 'Leg neu');

    expect(find.text('Übung'), findsNothing);
    expect(find.text('Leg'), findsOneWidget);
  });

  testWidgets('nach dem Schließen öffnet ein neuer Screen', (tester) async {
    await pumpShell(tester);
    await open(tester, 'workout:a', 'Leg alt');
    Navigator.of(shellContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await open(tester, 'workout:a', 'Leg neu');

    expect(find.text('Leg neu'), findsOneWidget);
  });
}
