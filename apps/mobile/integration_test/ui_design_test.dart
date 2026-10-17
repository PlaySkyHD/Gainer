import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ui_design_fixture.dart';
import 'ui_design_flow.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('programmatic tab changes keep routes and tab content in sync', (
    tester,
  ) async {
    final fixture = await createUiDesignFixture();
    addTearDown(fixture.dispose);
    await runProgrammaticTabChecks(tester, fixture, fixture.app);
  });

  testWidgets('captures populated native tabs and the check-in sheet', (
    tester,
  ) async {
    final fixture = await createUiDesignFixture();
    addTearDown(fixture.dispose);
    await runUiDesignCaptureFlow(
      tester,
      fixture,
      fixture.app,
      (name) => binding.takeScreenshot(name),
    );
  });
}
