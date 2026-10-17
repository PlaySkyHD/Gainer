import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';

/// WCAG 2.x Kontrastverhältnis aus der relativen Luminanz.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + .05) / (darker + .05);
}

void main() {
  for (final entry in {
    Brightness.light: GainerColors.light,
    Brightness.dark: GainerColors.dark,
  }.entries) {
    group('${entry.key.name} mode', () {
      final c = entry.value;
      final surfaces = {
        'background': c.background,
        'surface': c.surface,
        'elevatedSurface': c.elevatedSurface,
      };

      for (final surface in surfaces.entries) {
        test('primaryText on ${surface.key} is at least 4.5:1', () {
          expect(
            contrast(c.primaryText, surface.value),
            greaterThanOrEqualTo(4.5),
          );
        });

        test('secondaryText on ${surface.key} is at least 4.5:1', () {
          expect(
            contrast(c.secondaryText, surface.value),
            greaterThanOrEqualTo(4.5),
          );
        });
      }

      test('accent on background and surface is at least 3:1', () {
        expect(contrast(c.accent, c.background), greaterThanOrEqualTo(3));
        expect(contrast(c.accent, c.surface), greaterThanOrEqualTo(3));
      });

      test('onAccent on accent is at least 4.5:1', () {
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
      });

      test('destructive on surface meets the mode threshold', () {
        final threshold = entry.key == Brightness.light ? 4.5 : 3.0;
        expect(
          contrast(c.destructive, c.surface),
          greaterThanOrEqualTo(threshold),
        );
      });

      test('placeholderText is clearly distinct from primaryText', () {
        expect(
          contrast(c.placeholderText, c.primaryText),
          greaterThanOrEqualTo(1.8),
        );
      });
    });
  }
}
