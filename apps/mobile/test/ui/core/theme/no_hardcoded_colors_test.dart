import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Übergangs-Allowlist: Dateien mit festen Farben außerhalb von `ui/core/theme/`.
/// Aktuell leer, weil die bisherige Stelle (`ui/core/theme.dart`) auf Farbrollen
/// umgestellt ist. Neue Einträge sind nicht vorgesehen.
const _legacyAllowlist = <String>{};

final _forbidden = RegExp(r'Color\(0x|Color\.fromARGB|Color\.fromRGBO');

void main() {
  test('no hardcoded colors outside the theme folder', () {
    final root = Directory('lib');
    final offenders = <String>[];

    for (final file in root.listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      if (path.contains('lib/ui/core/theme/')) continue;
      if (_legacyAllowlist.any(path.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_forbidden.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Farben nur über Farbrollen in ui/core/theme/ beziehen:\n${offenders.join('\n')}',
    );
  });
}
