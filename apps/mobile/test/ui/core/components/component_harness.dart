import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

/// Rahmen mit Helligkeit und Textskalierung wie in der App (CupertinoApp + GainerDesign).
Widget componentHarness({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return CupertinoApp(
    debugShowCheckedModeBanner: false,
    theme: GainerTheme.forBrightness(brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: brightness,
          textScaler: TextScaler.linear(textScale),
        ),
        child: GainerDesign(
          child: ColoredBox(
            color: GainerDesign.colorsOf(context).background,
            child: Padding(
              padding: const EdgeInsets.all(GainerSpacing.m),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Golden-Varianten je Komponente: hell, dunkel und Textskalierung 2.0.
const goldenVariants = <({String suffix, Brightness brightness, double scale})>[
  (suffix: 'light', brightness: Brightness.light, scale: 1),
  (suffix: 'dark', brightness: Brightness.dark, scale: 1),
  (suffix: 'text_scale_2', brightness: Brightness.light, scale: 2),
];

void expectGoldenVariants(
  String name,
  Widget Function() build, {
  Size size = const Size(390, 844),
}) {
  for (final variant in goldenVariants) {
    testWidgets('$name ${variant.suffix}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: componentHarness(
            child: build(),
            brightness: variant.brightness,
            textScale: variant.scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(boundary),
        matchesGoldenFile('goldens/${name}_${variant.suffix}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

/// Die Enter-Taste ist die Standardbestätigung der Tastatur; Dialoge dürfen darauf nicht reagieren.
Future<void> pressReturn(WidgetTester tester) =>
    tester.sendKeyEvent(LogicalKeyboardKey.enter);
