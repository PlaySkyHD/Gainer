import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_day_kind.dart';

void main() {
  String labelOf(WidgetTester tester) => tester
      .getSemantics(find.byKey(const ValueKey('nutrition-day-kind-chip')))
      .label
      .trim();

  testWidgets('Chip mit Aktion hängt „Ändern“ an die Beschriftung', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      CupertinoApp(
        home: NutritionDayKindChip(
          kind: NutritionDayKind.training,
          manual: true,
          onTap: () {},
        ),
      ),
    );
    expect(
      labelOf(tester),
      'Tagesart: Trainingstag, manuell festgelegt. Ändern',
    );
    handle.dispose();
  });

  testWidgets('Chip ohne Aktion verspricht kein „Ändern“', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const CupertinoApp(
        home: NutritionDayKindChip(
          kind: NutritionDayKind.rest,
          manual: false,
          onTap: null,
        ),
      ),
    );
    expect(labelOf(tester), 'Tagesart: Ruhetag');
    handle.dispose();
  });
}
