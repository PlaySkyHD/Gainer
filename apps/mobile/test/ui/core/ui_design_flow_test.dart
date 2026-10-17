import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/ui_design_fixture.dart';
import '../../../integration_test/ui_design_flow.dart';

/// Führt dieselben Abläufe wie der Simulator-Test auf dem Widget-Test-Binding
/// aus, ohne Screenshots. Die Größe entspricht dem Preview-Test.
void main() {
  testWidgets('programmatic tab changes run on the widget test binding', (
    tester,
  ) async {
    _usePhoneView(tester);
    final fixture = await _createFixture(tester);
    try {
      await runProgrammaticTabChecks(tester, fixture, fixture.app);
    } finally {
      await _disposeFixture(tester, fixture);
    }
  });

  testWidgets('capture flow runs on the widget test binding', (tester) async {
    _usePhoneView(tester);
    final fixture = await _createFixture(tester);
    try {
      await runUiDesignCaptureFlow(tester, fixture, fixture.app, (_) async {});
    } finally {
      await _disposeFixture(tester, fixture);
    }
  });
}

void _usePhoneView(WidgetTester tester) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(786, 1704);
  tester.view.viewPadding = const FakeViewPadding(top: 118, bottom: 68);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
}

Future<UiDesignFixture> _createFixture(WidgetTester tester) async {
  final fixture = await tester.runAsync(createUiDesignFixture);
  if (fixture == null) {
    throw StateError('Could not create the UI design fixture.');
  }
  return fixture;
}

Future<void> _disposeFixture(
  WidgetTester tester,
  UiDesignFixture fixture,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(fixture.dispose);
}
