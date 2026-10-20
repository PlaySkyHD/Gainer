import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/access/logout_everywhere.dart';

void main() {
  Future<void> open(WidgetTester tester, Future<void> Function() action) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => confirmLogoutEverywhere(context, action),
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }

  testWidgets('signs every device out after confirming', (tester) async {
    var calls = 0;
    await open(tester, () async => calls++);

    expect(find.text('Auf allen Geräten abmelden?'), findsOneWidget);
    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Abmelden nicht möglich'), findsNothing);
  });

  testWidgets('cancelling does nothing', (tester) async {
    var calls = 0;
    await open(tester, () async => calls++);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('explains a failure and keeps the device signed in', (
    tester,
  ) async {
    await open(tester, () async => throw StateError('offline'));

    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();

    expect(find.text('Abmelden nicht möglich'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Abmelden nicht möglich'), findsNothing);
  });
}
