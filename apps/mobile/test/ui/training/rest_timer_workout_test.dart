import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/timer/rest_timer_state.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/compact_training_bar.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_bar.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_controller.dart';
import 'package:gainer_mobile/ui/features/training/rest_timer_sheet.dart';
import 'package:gainer_mobile/ui/features/training/training_home_view_model.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_view_model.dart';

import 'rest_timer_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

/// Aktives Training mit Pausentimern aus dem Test-Fixture, so wie der
/// Übung mit einem leeren Satz. `strengthBlock` füllt Werte vor und wäre sofort vollständig.
WorkoutBlock _emptyBench() => WorkoutBlock(
  workoutExerciseId: 'bench',
  sourceExerciseId: 'bench-source',
  exerciseNameSnapshot: 'Bankdrücken',
  exerciseTypeSnapshot: ExerciseKind.strength,
  sets: [LoggedSet(setId: 'bench-set-0')],
);

/// Alle Zahlenfelder der Seite in Lesereihenfolge (Kg, Wdh.).
Finder _field(int index) => find.byType(CupertinoTextField).at(index);

EditableTextState _editable(WidgetTester tester, int index) =>
    tester.state<EditableTextState>(
      find.descendant(of: _field(index), matching: find.byType(EditableText)),
    );

bool _hasFocus(WidgetTester tester, int index) =>
    _editable(tester, index).widget.focusNode.hasFocus;

String _text(WidgetTester tester, int index) =>
    _editable(tester, index).widget.controller.text;

/// Finder über das Semantics-Widget mit diesem Label.
Finder _labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Simuliert eine sichtbare Zahlentastatur, wie sie das Gerät über die Insets meldet.
void _showKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetViewInsets);
}

Finder _compactBar() => find.byKey(const ValueKey('compact-training-bar'));

void main() {
  late TrainingHarness harness;
  late RestTimerFixture fixture;
  late ActiveWorkoutController active;
  var activeDisposed = false;

  /// Gibt das Training einmal frei; Tests mit eigenem Lebenszyklus rufen es selbst.
  void disposeActive() {
    if (activeDisposed) return;
    activeDisposed = true;
    active.dispose();
  }

  setUp(() async {
    harness = await TrainingHarness.create();
    fixture = RestTimerFixture();
    active = activeWorkoutWithTimers(harness, fixture);
    activeDisposed = false;
  });

  tearDown(() async {
    disposeActive();
    fixture.disposeControllers();
    await harness.dispose();
  });

  Future<String> seedActive({List<WorkoutBlock> blocks = const []}) async {
    final workout = await harness.seedWorkout(
      title: 'Push',
      start: DateTime.utc(2026, 10, 17, 8),
      blocks: blocks,
    );
    await active.load();
    return workout.workoutId;
  }

  Future<void> pumpWorkout(WidgetTester tester, String workoutId) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      trainingTestApp(
        home: WorkoutScreen(
          repository: harness.repository,
          activeWorkout: active,
          workoutId: workoutId,
        ),
      ),
    );
    await settle(tester);
  }

  /// Startet den Pausentimer mit der Dauer [seconds].
  Future<RestTimerController> startTimer(int seconds) async {
    final timer = active.restTimer!;
    await timer.startShortcut(seconds);
    return timer;
  }

  testWidgets('Timeransicht öffnen und schließen behält Fokus und Eingabe', (
    tester,
  ) async {
    final id = await seedActive(
      blocks: [strengthBlock('Bankdrücken', 1, id: 'bench')],
    );
    await pumpWorkout(tester, id);
    await startTimer(180);
    await settle(tester);

    _showKeyboard(tester);
    await tester.tap(_field(0));
    await settle(tester);
    await tester.enterText(_field(0), '82,5');
    await settle(tester);
    expect(_hasFocus(tester, 0), isTrue);

    await tester.tap(find.byType(RestTimerBar));
    await settle(tester);
    expect(find.byType(RestTimerSheet), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(RestTimerSheet),
        matching: _labelled('Timer schließen'),
      ),
    );
    await settle(tester);

    expect(find.byType(RestTimerSheet), findsNothing);
    expect(_hasFocus(tester, 0), isTrue);
    expect(_text(tester, 0), '82,5');
  });

  testWidgets('Timer ohne sichtbare Tastatur: nach Schließen kein Fokus', (
    tester,
  ) async {
    final id = await seedActive(
      blocks: [strengthBlock('Bankdrücken', 1, id: 'bench')],
    );
    await pumpWorkout(tester, id);
    await startTimer(180);
    await settle(tester);

    await tester.tap(_field(0));
    await settle(tester);
    expect(_hasFocus(tester, 0), isTrue);

    await tester.tap(find.byType(RestTimerBar));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(RestTimerSheet),
        matching: _labelled('Timer schließen'),
      ),
    );
    await settle(tester);

    expect(find.byType(RestTimerSheet), findsNothing);
    expect(_hasFocus(tester, 0), isFalse);
  });

  testWidgets(
    'Weiter: das neu fokussierte Satzfeld liegt oberhalb der Leisten',
    (tester) async {
      final id = await seedActive(
        blocks: [strengthBlock('Bankdrücken', 8, id: 'bench')],
      );
      await pumpWorkout(tester, id);
      await startTimer(180);
      _showKeyboard(tester);
      await settle(tester);

      await tester.tap(_field(0));
      await settle(tester);
      for (var step = 0; step < 9; step++) {
        await tester.tap(_labelled('Weiter'));
        await settle(tester);
      }

      expect(_hasFocus(tester, 9), isTrue);
      final field = tester.getRect(_field(9));
      final bars = tester.getRect(find.byType(RestTimerBar));
      final accessory = tester.getRect(find.byType(GainerNumericAccessoryBar));
      expect(field.bottom, lessThanOrEqualTo(bars.top));
      expect(field.bottom, lessThanOrEqualTo(accessory.top));
      expect(field.top, greaterThanOrEqualTo(0));
      disposeActive();
    },
  );

  testWidgets(
    'abgelaufener Timer bleibt bei 00:00, bis der Satz vollständig ist',
    (tester) async {
      final id = await seedActive(blocks: [_emptyBench()]);
      await pumpWorkout(tester, id);
      await startTimer(60);
      await advanceRestTimer(tester, fixture.clock, 61);
      await settle(tester);
      expect(active.restTimer!.phase, RestTimerPhase.expired);
      expect(find.text('00:00'), findsOneWidget);

      await tester.tap(_field(0));
      await settle(tester);
      await tester.enterText(_field(0), '80');
      await settle(tester);
      expect(find.text('00:00'), findsOneWidget);
      expect(active.restTimer!.phase, RestTimerPhase.expired);

      await tester.tap(_field(1));
      await settle(tester);
      await tester.enterText(_field(1), '8');
      await settle(tester);
      expect(find.text('00:00'), findsNothing);
      expect(active.restTimer!.phase, RestTimerPhase.ready);
    },
  );

  testWidgets(
    'minimieren mit laufendem Timer: Controller lebt, Leiste zeigt dieselbe Restzeit',
    (tester) async {
      final id = await seedActive();
      final host = Builder(
        builder: (context) => Center(
          child: CupertinoButton(
            onPressed: () => openWorkoutScreen(
              context,
              repository: harness.repository,
              activeWorkout: active,
              workoutId: id,
            ),
            child: const Text('Öffnen'),
          ),
        ),
      );
      usePhoneSize(tester);
      await tester.pumpWidget(
        trainingTestApp(
          home: Column(
            children: [
              Expanded(child: host),
              CompactTrainingBar(
                activeWorkout: active,
                repository: harness.repository,
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      final timer = await startTimer(180);

      await tester.tap(find.text('Öffnen'));
      await settle(tester);
      await advanceRestTimer(tester, fixture.clock, 30);
      await settle(tester);
      await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
      await settle(tester);

      expect(identical(active.restTimer, timer), isTrue);
      expect(timer.phase, RestTimerPhase.running);
      expect(
        find.descendant(of: _compactBar(), matching: find.text('02:30')),
        findsOneWidget,
      );

      await tester.tap(_compactBar());
      await settle(tester);

      expect(identical(active.restTimer, timer), isTrue);
      expect(find.text('02:30'), findsOneWidget);
      disposeActive();
    },
  );

  testWidgets('Training löschen aus dem Menü beendet den Pausentimer', (
    tester,
  ) async {
    final id = await seedActive();
    final timer = await startTimer(120);
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('Löschen').last);
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(GainerStackedDialog<bool>),
        matching: find.text('Löschen'),
      ),
    );
    await settle(tester);

    expect(active.restTimer, isNull);
    expect(timer.phase, RestTimerPhase.ready);
    expect(fixture.notifications.cancelCount, greaterThan(0));
  });

  test('Beenden beendet den Pausentimer', () async {
    final id = await seedActive();
    final timer = await startTimer(120);
    harness.now = DateTime.utc(2026, 10, 17, 9);
    final model = WorkoutViewModel(
      repository: harness.repository,
      activeWorkout: active,
      workoutId: id,
    );
    await model.load();

    final outcome = await model.requestFinish();

    expect(outcome, WorkoutFinishOutcome.finished);
    expect(active.restTimer, isNull);
    expect(timer.phase, RestTimerPhase.ready);
    expect(fixture.notifications.cancelCount, greaterThan(0));
    model.dispose();
  });

  test('Löschen im Tagebuch beendet den Pausentimer', () async {
    final id = await seedActive();
    final timer = await startTimer(120);
    final home = TrainingHomeViewModel(
      repository: harness.repository,
      activeWorkout: active,
    );
    await home.loadDiary();

    await home.deleteWorkout(id);

    expect(active.restTimer, isNull);
    expect(timer.phase, RestTimerPhase.ready);
    expect(fixture.notifications.cancelCount, greaterThan(0));
    home.dispose();
  });

  test('Kontowechsel: Dispose des Kontos entsorgt den Pausentimer', () async {
    await seedActive();
    final timer = await startTimer(120);

    disposeActive();
    await Future<void>.delayed(Duration.zero);

    expect(active.restTimer, isNull);
    expect(fixture.notifications.cancelCount, greaterThan(0));
    final before = timer.state;
    await timer.stop();
    expect(identical(timer.state, before), isTrue);
  });

  testWidgets('Menü: Wiederholen nur bei beendetem Training', (tester) async {
    final historic = await harness.seedWorkout(
      title: 'Legs 2',
      start: DateTime.utc(2026, 10, 15, 18),
      end: DateTime.utc(2026, 10, 15, 19),
    );
    await active.load();
    await pumpWorkout(tester, historic.workoutId);

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);

    expect(find.text('Training wiederholen'), findsOneWidget);
    expect(find.text('Als Trainingsplan speichern'), findsOneWidget);
  });

  testWidgets('Menü: aktives Training bietet kein Wiederholen', (tester) async {
    final id = await seedActive();
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);

    expect(find.text('Training wiederholen'), findsNothing);
    expect(find.text('Als Trainingsplan speichern'), findsOneWidget);
    expect(find.textContaining('Gewichtseinheit'), findsOneWidget);
    expect(find.text('RIR anzeigen'), findsOneWidget);
  });
}
