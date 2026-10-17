import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

void main() {
  testWidgets('GainerDesign provides different roles for light and dark', (
    tester,
  ) async {
    late GainerColors colors;
    Widget app() => CupertinoApp(
      builder: (context, child) => GainerDesign(child: child!),
      home: Builder(
        builder: (context) {
          colors = GainerDesign.colorsOf(context);
          return const SizedBox.shrink();
        },
      ),
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(app());
    expect(colors.background, GainerColors.light.background);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.binding.handlePlatformBrightnessChanged();
    await tester.pump();
    expect(colors.background, GainerColors.dark.background);
    expect(colors.background, isNot(GainerColors.light.background));
  });

  testWidgets(
    'a system brightness change keeps the text field value and focus',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) => GainerDesign(child: child!),
          home: CupertinoPageScaffold(
            child: Center(
              child: CupertinoTextField(
                key: const ValueKey('weight'),
                controller: controller,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('weight')));
      await tester.enterText(find.byKey(const ValueKey('weight')), '82,5');
      await tester.pump();

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.binding.handlePlatformBrightnessChanged();
      await tester.pump();

      expect(controller.text, '82,5');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
    },
  );
}
