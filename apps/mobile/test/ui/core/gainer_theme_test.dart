import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + .05) / (darker + .05);
}

void main() {
  test(
    'accent keeps on-accent text readable and is visible on the background',
    () {
      expect(
        _contrast(GainerColors.light.onAccent, GainerColors.light.accent),
        greaterThanOrEqualTo(4.5),
      );
      for (final theme in [GainerTheme.light, GainerTheme.dark]) {
        expect(
          _contrast(theme.primaryColor, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(3),
        );
      }
    },
  );

  testWidgets('secondary text is readable on light and dark neutral surfaces', (
    tester,
  ) async {
    for (final theme in [GainerTheme.light, GainerTheme.dark]) {
      late Color secondary;
      late Color card;
      late Color field;
      await tester.pumpWidget(
        CupertinoApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              secondary = GainerTheme.secondaryText(context);
              card = CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context);
              field = CupertinoColors.tertiarySystemGroupedBackground
                  .resolveFrom(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      for (final background in [theme.scaffoldBackgroundColor, card, field]) {
        expect(
          _contrast(secondary, background),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness} secondary text on $background',
        );
      }
    }
  });
}
