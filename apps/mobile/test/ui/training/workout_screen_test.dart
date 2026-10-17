import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/compact_training_bar.dart';
import 'package:gainer_mobile/ui/features/training/training_diary_section.dart';
import 'package:gainer_mobile/ui/features/training/training_home_screen.dart';

import 'training_test_support.dart';

/// Shell-Ausschnitt: Trainings-Tab, ein zweiter Tab und die Trainingsleiste darüber.
Widget _shell(
  TrainingHarness harness,
  ActiveWorkoutController activeWorkout,
  MobileShellViewModel model,
) => MobileTabScaffold(
  model: model,
  compactTrainingBar: CompactTrainingBar(
    activeWorkout: activeWorkout,
    repository: harness.repository,
  ),
  tabBuilder: (context, area) => switch (area) {
    MobileArea.training => TrainingHomeScreen(
      repository: harness.repository,
      activeWorkout: activeWorkout,
    ),
    _ => const CupertinoPageScaffold(
      child: Center(child: Text('Heute-Inhalt')),
    ),
  },
);

Finder _diaryRow(String title) => find.descendant(
  of: find.byType(TrainingDiarySection),
  matching: find.text(title),
);

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;
  late MobileShellViewModel model;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
    model = MobileShellViewModel();
  });

  tearDown(() async {
    model.dispose();
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    model.selectTab(MobileArea.training.index);
    await tester.pumpWidget(
      trainingTestApp(home: _shell(harness, activeWorkout, model)),
    );
    await settle(tester);
  }

  Future<void> startActiveWorkout(
    String title, {
    Duration ago = Duration.zero,
  }) => harness.seedWorkout(
    title: title,
    start: DateTime.now().toUtc().subtract(ago),
  );

  testWidgets('aktives Training zeigt Minimieren, Beenden und Menü', (
    tester,
  ) async {
    await tester.runAsync(() => startActiveWorkout('Push'));
    await tester.runAsync(activeWorkout.load);
    await pumpShell(tester);

    await tester.tap(_diaryRow('Push'));
    await settle(tester);

    expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    expect(find.text('Beenden'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark), findsNothing);
    expect(find.byIcon(CupertinoIcons.timer), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
  });

  testWidgets('minimiert bleibt aktiv, Leiste erscheint in anderem Tab', (
    tester,
  ) async {
    await tester.runAsync(
      () => startActiveWorkout(
        'Push',
        ago: const Duration(minutes: 12, seconds: 34),
      ),
    );
    await tester.runAsync(activeWorkout.load);
    await pumpShell(tester);

    await tester.tap(_diaryRow('Push'));
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
    await settle(tester);

    expect(find.text('Beenden'), findsNothing);
    await tester.tap(find.text('Heute'));
    await settle(tester);

    expect(find.text('Heute-Inhalt'), findsOneWidget);
    final bar = find.byKey(const ValueKey('compact-training-bar'));
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.text('Push')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data ?? '').startsWith('12:3'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(bar);
    await settle(tester);
    expect(find.text('Beenden'), findsOneWidget);
  });

  testWidgets('Leiste ist nach Neustart wiederhergestellt', (tester) async {
    await tester.runAsync(() => startActiveWorkout('Push'));
    // Neuer Controller auf derselben Datenbank entspricht einem App-Neustart.
    final restarted = ActiveWorkoutController(harness.repository);
    addTearDown(restarted.dispose);
    await tester.runAsync(restarted.load);
    await tester.pumpWidget(
      trainingTestApp(
        home: CompactTrainingBar(
          activeWorkout: restarted,
          repository: harness.repository,
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Push'), findsOneWidget);
  });

  testWidgets('historisches Training zeigt Haken statt Beenden', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Legs 2',
        start: DateTime(2026, 10, 15, 18).toUtc(),
        end: DateTime(2026, 10, 15, 19).toUtc(),
      ),
    );
    await pumpShell(tester);

    await tester.tap(_diaryRow('Legs 2'));
    await settle(tester);

    expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
    expect(find.text('Beenden'), findsNothing);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsNothing);
    expect(find.text('15. Okt.'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.checkmark));
    await settle(tester);
    expect(find.text('Beenden'), findsNothing);
    expect(find.text('Legs 2'), findsOneWidget);
  });

  testWidgets('Beenden schließt den Screen und entfernt die Leiste', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push',
        start: DateTime.utc(2026, 10, 17, 8),
      ),
    );
    await tester.runAsync(activeWorkout.load);
    await pumpShell(tester);

    await tester.tap(_diaryRow('Push'));
    await settle(tester);
    harness.now = DateTime.utc(2026, 10, 17, 9);
    await tester.tap(find.text('Beenden'));
    await settle(tester);

    expect(find.text('Beenden'), findsNothing);
    expect(find.byKey(const ValueKey('compact-training-bar')), findsNothing);
    final active = await tester.runAsync(harness.repository.readActiveWorkout);
    expect(active, isNull);
    expect(tester.takeException(), isNull);
  });
}
