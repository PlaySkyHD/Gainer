import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  testWidgets(
    'Leiste erscheint bei offener Tastatur, Inset stimmt nach dem Frame',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final model = MobileShellViewModel();
      addTearDown(model.dispose);
      final showBar = ValueNotifier<bool>(false);
      addTearDown(showBar.dispose);
      double? inset;

      await tester.pumpWidget(
        CupertinoApp(
          theme: GainerTheme.light,
          home: MobileTabScaffold(
            model: model,
            compactTrainingBar: ValueListenableBuilder<bool>(
              valueListenable: showBar,
              builder: (context, visible, child) =>
                  SizedBox(height: visible ? 80 : 0),
            ),
            tabBuilder: (context, area) {
              inset = MediaQuery.of(context).viewInsets.bottom;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final withoutBar = inset!;

      showBar.value = true;
      await tester.pumpAndSettle();
      expect(inset, withoutBar - 80);

      showBar.value = false;
      await tester.pumpAndSettle();
      expect(inset, withoutBar);
      expect(tester.takeException(), isNull);
    },
  );
}
