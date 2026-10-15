import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('../../artifacts/mobile/ui-captures');
  await output.create(recursive: true);
  // Flutter Driver's initial VM-service connection happens before the
  // integration test emits any output. Keep a host-side breadcrumb so a
  // bounded CI timeout identifies whether the app ever became reachable.
  stdout.writeln(
    'UI capture driver: waiting for the simulator app VM service.',
  );
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      stdout.writeln(
        'UI capture driver: saving screenshot $name (${bytes.length} bytes).',
      );
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
