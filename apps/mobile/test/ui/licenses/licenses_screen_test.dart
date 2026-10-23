import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/licenses/licenses_screen.dart';

void main() {
  testWidgets('names the BLS source, DOI and licence', (tester) async {
    await tester.pumpWidget(const CupertinoApp(home: LicensesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Bundeslebensmittelschlüssel 4.0'), findsOneWidget);
    expect(find.text('Max Rubner-Institut · CC BY 4.0'), findsOneWidget);
    expect(
      find.textContaining(
        'Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('10.25826/Data20251217-134202-0'),
      findsOneWidget,
    );
    expect(find.text('Open Food Facts'), findsOneWidget);
  });
}
