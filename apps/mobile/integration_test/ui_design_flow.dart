import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

import 'ui_design_fixture.dart';

/// Baut die App für ein Theme. Integrationstests nutzen `fixture.app`, die
/// Preview-Tests zusätzlich eine RepaintBoundary.
typedef UiDesignAppBuilder = Widget Function(CupertinoThemeData theme);

/// Speichert einen Screenshot unter dem genannten Namen.
typedef UiDesignCapture = Future<void> Function(String name);

/// Prüft die programmatischen Tabwechsel und deren Routen.
Future<void> runProgrammaticTabChecks(
  WidgetTester tester,
  UiDesignFixture fixture,
  UiDesignAppBuilder app,
) async {
  await tester.pumpWidget(app(GainerTheme.light));
  await tester.pumpAndSettle();
  await _tapTab(tester, 'Essen');
  await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);

  fixture.controller.shell.selectTab(MobileArea.body.index);
  await tester.pumpAndSettle();
  expect(find.text('Verlauf'), findsOneWidget);
  fixture.controller.shell.selectTab(MobileArea.nutrition.index);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
  expect(
    fixture.controller.shell.tabController.index,
    MobileArea.nutrition.index,
  );
}

/// Durchläuft die Hauptbereiche in Hell- und Dunkel-Darstellung mit
/// Fixture-Daten und speichert nach jedem Zielzustand einen Screenshot.
Future<void> runUiDesignCaptureFlow(
  WidgetTester tester,
  UiDesignFixture fixture,
  UiDesignAppBuilder app,
  UiDesignCapture capture,
) async {
  await tester.pumpWidget(app(GainerTheme.light));
  await tester.pumpAndSettle();
  await _waitForExerciseProgress(tester, fixture);
  await capture('tab-heute');
  expect(find.text('Dein Fortschritt aus deinen Einträgen'), findsOneWidget);
  expect(find.text('Letzter Eintrag · 14.10.2026'), findsOneWidget);
  expect(find.text('Ø 7 Tage · 82.7 kg'), findsOneWidget);
  await _scrollActiveTabUntilVisible(
    tester,
    find.text('148 g Protein pro erfasstem Tag'),
  );
  expect(find.text('148 g Protein pro erfasstem Tag'), findsOneWidget);
  _resetActiveTabScroll(tester);
  await tester.pumpAndSettle();
  await _scrollActiveTabUntilVisible(tester, find.text('Übungsfortschritt'));
  await capture('exercise-progress');
  expect(
    fixture.account.progressViewModel.exerciseProgress!.points,
    isNotEmpty,
  );

  await _tapTab(tester, 'Check-in');
  expect(find.text('Verlauf'), findsOneWidget);
  await capture('tab-checkin');
  await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('body-save-checkin')), findsOneWidget);
  await capture('sheet-checkin');
  await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
  await tester.pumpAndSettle();
  await _scrollActiveTabUntilVisible(
    tester,
    find.byKey(const ValueKey('body-open-goal')),
  );
  await tester.tap(find.byKey(const ValueKey('body-open-goal')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('body-save-goal')), findsOneWidget);
  await capture('sheet-goal');
  await tester.tap(find.byKey(const ValueKey('body-start-date')));
  await tester.pumpAndSettle();
  expect(find.text('Fertig'), findsOneWidget);
  await capture('date-picker');
  await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
  await tester.pumpAndSettle();

  await _tapTab(tester, 'Essen');
  await capture('tab-essen');
  await _scrollActiveTabUntilVisible(
    tester,
    find.byKey(const ValueKey('nutrition-add-food')),
  );
  await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('nutrition-entry-name')),
  );
  expect(find.byKey(const ValueKey('nutrition-entry-name')), findsOneWidget);
  await capture('editor-essen');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  _resetActiveTabScroll(tester);
  await tester.pumpAndSettle();
  expect(find.text('Ernährungstagebuch'), findsOneWidget);

  // Tagebuch ist leer; „Training starten“ öffnet den Trainingsscreen, der
  // sich danach minimieren lässt und als kompakte Leiste über der Tableiste
  // weiterläuft.
  await _tapTab(tester, 'Training');
  expect(find.text('Noch keine Trainings'), findsOneWidget);
  await capture('tab-training');
  await tester.tap(find.byKey(const ValueKey('training-start-empty')));
  await tester.pumpAndSettle();
  expect(find.text('Beenden'), findsOneWidget);
  await capture('training-workout');
  await tester.tap(_minimizeWorkoutButton);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('compact-training-bar')), findsOneWidget);
  await capture('training-minimized');

  await _tapTab(tester, 'Mehr');
  await capture('tab-mehr');
  await _scrollActiveTabUntilVisible(tester, find.text('Apple Health'));
  expect(find.text('Apple Health'), findsOneWidget);
  expect(tester.takeException(), isNull);

  // Alle Hauptbereiche erneut unter dunkler Darstellung.
  await tester.pumpWidget(app(GainerTheme.dark));
  await tester.pumpAndSettle();
  for (final tab in const [
    ('Heute', 'tab-dark-heute'),
    ('Check-in', 'tab-dark-checkin'),
    ('Essen', 'tab-dark-essen'),
    ('Training', 'tab-dark-training'),
    ('Mehr', 'tab-dark-mehr'),
  ]) {
    await _tapTab(tester, tab.$1);
    _resetActiveTabScroll(tester);
    await tester.pumpAndSettle();
    if (tab.$1 == 'Heute') {
      expect(
        find.text('Dein Fortschritt aus deinen Einträgen'),
        findsOneWidget,
      );
    }
    await capture(tab.$2);
  }
  await _tapTab(tester, 'Heute');
  await _scrollActiveTabUntilVisible(tester, find.text('Übungsfortschritt'));
  await capture('exercise-dark-progress');
  expect(
    fixture.account.progressViewModel.exerciseProgress!.points,
    isNotEmpty,
  );
  await _tapTab(tester, 'Check-in');
  await tester.tap(find.byKey(const ValueKey('body-open-checkin')));
  await tester.pumpAndSettle();
  await capture('sheet-dark-checkin');
  await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
  await tester.pumpAndSettle();

  await _tapTab(tester, 'Essen');
  await _scrollActiveTabUntilVisible(
    tester,
    find.byKey(const ValueKey('nutrition-add-food')),
  );
  await tester.tap(find.byKey(const ValueKey('nutrition-add-food')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nutrition-mode-manual')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('nutrition-entry-name')),
  );
  await capture('editor-dark-essen');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Das Minimieren-Icon des Trainingsscreens ist nur über sein Semantik-Label
/// eindeutig; Icons allein kommen mehrfach vor.
Finder get _minimizeWorkoutButton => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Minimieren',
);

/// Der vertikale Scrollbereich des aktiven Tabs. Inaktive Tabs liegen
/// offstage und sind nicht hit-testbar; der äußere Bereich kommt zuerst.
Finder _activeTabScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    )
    .hitTestable()
    .first;

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _scrollActiveTabUntilVisible(
  WidgetTester tester,
  Finder target,
) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: _activeTabScrollable(),
    maxScrolls: 20,
  );
  await tester.pumpAndSettle();
}

void _resetActiveTabScroll(WidgetTester tester) {
  tester.state<ScrollableState>(_activeTabScrollable()).position.jumpTo(0);
}

Future<void> _waitForExerciseProgress(
  WidgetTester tester,
  UiDesignFixture fixture,
) async {
  final viewModel = fixture.account.progressViewModel;
  for (
    var attempt = 0;
    attempt < 30 &&
        (viewModel.dashboard == null || viewModel.exerciseProgress == null);
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(viewModel.dashboard, isNotNull);
  expect(viewModel.selectedExerciseId, isNotNull);
  expect(viewModel.selectedProgressWindow, '30');
  expect(viewModel.exerciseOptions, isNotEmpty);
  expect(viewModel.exerciseProgress, isNotNull);
  expect(viewModel.exerciseProgress!.points, isNotEmpty);
}
