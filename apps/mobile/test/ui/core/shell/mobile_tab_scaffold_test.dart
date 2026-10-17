import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  testWidgets('Tab wechseln', (tester) async {
    final semantics = tester.ensureSemantics();
    final model = MobileShellViewModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: MobileTabScaffold(
          model: model,
          tabBuilder: (context, area) => CupertinoPageScaffold(
            child: Center(child: Text('Inhalt ${area.label}')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inhalt Heute'), findsOneWidget);
    expect(find.text('Inhalt Training'), findsNothing);
    expect(_isSelected(tester, 'Heute'), isTrue);

    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();

    expect(model.selectedArea, MobileArea.training);
    expect(find.text('Inhalt Training'), findsOneWidget);
    expect(find.text('Inhalt Heute'), findsNothing);
    expect(_isSelected(tester, 'Training'), isTrue);
    expect(_isSelected(tester, 'Heute'), isFalse);
    semantics.dispose();
  });

  testWidgets('reservierter Slot liegt über der Tableiste', (tester) async {
    final model = MobileShellViewModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: MobileTabScaffold(
          model: model,
          compactTrainingBar: const Text('Trainingsleiste'),
          tabBuilder: (context, area) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slot = tester.getTopLeft(find.text('Trainingsleiste'));
    final tabBar = tester.getTopLeft(find.text('Heute'));
    expect(slot.dy, lessThan(tabBar.dy));
  });
}

bool _isSelected(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  return node.flagsCollection.isSelected == Tristate.isTrue;
}
