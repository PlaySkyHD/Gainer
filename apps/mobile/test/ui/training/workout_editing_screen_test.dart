import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';
import 'package:gainer_mobile/ui/features/training/exercise_statistics_screen.dart';
import 'package:gainer_mobile/ui/features/training/workout_metadata_card.dart';
import 'package:gainer_mobile/ui/features/training/workout_screen.dart';

import 'training_test_support.dart';

WorkoutBlock _block(
  String id,
  String sourceId,
  String name,
  ExerciseKind kind,
  List<LoggedSet> sets, {
  String? supersetId,
}) => WorkoutBlock(
  workoutExerciseId: id,
  sourceExerciseId: sourceId,
  exerciseNameSnapshot: name,
  exerciseTypeSnapshot: kind,
  supersetId: supersetId,
  sets: sets,
);

/// Alle Zahlenfelder der Seite in Lesereihenfolge (Kg, Wdh., RIR).
Finder _fields() => find.byType(CupertinoTextField);

Finder _field(int index) => _fields().at(index);

/// Finder über das Semantics-Widget mit diesem Label; funktioniert ohne
/// aktivierten Semantikbaum.
Finder _labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

EditableTextState _editable(WidgetTester tester, int index) =>
    tester.state<EditableTextState>(
      find.descendant(of: _field(index), matching: find.byType(EditableText)),
    );

String _text(WidgetTester tester, int index) =>
    _editable(tester, index).widget.controller.text;

bool _hasFocus(WidgetTester tester, int index) =>
    _editable(tester, index).widget.focusNode.hasFocus;

/// Semantikwerte aller Knoten unterhalb von [root], etwa „Vorwert 100“.
Iterable<String> _semanticsValues(SemanticsNode root) sync* {
  if (root.value.isNotEmpty) yield root.value;
  final children = <SemanticsNode>[];
  root.visitChildren((child) {
    children.add(child);
    return true;
  });
  for (final child in children) {
    yield* _semanticsValues(child);
  }
}

void main() {
  late TrainingHarness harness;
  late ActiveWorkoutController activeWorkout;

  setUp(() async {
    harness = await TrainingHarness.create();
    activeWorkout = ActiveWorkoutController(harness.repository);
  });

  tearDown(() async {
    activeWorkout.dispose();
    await harness.dispose();
  });

  Future<String> seedActive(
    WidgetTester tester, {
    String title = 'Push',
    List<WorkoutBlock> blocks = const [],
    DateTime? start,
    DateTime? end,
  }) async {
    final workout = await tester.runAsync(
      () => harness.seedWorkout(
        title: title,
        start: start ?? DateTime.utc(2026, 10, 16, 8),
        end: end,
        blocks: blocks,
      ),
    );
    await tester.runAsync(activeWorkout.load);
    return workout!.workoutId;
  }

  Future<void> pumpWorkout(
    WidgetTester tester,
    String workoutId, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      trainingTestApp(
        brightness: brightness,
        textScale: textScale,
        home: WorkoutScreen(
          repository: harness.repository,
          activeWorkout: activeWorkout,
          workoutId: workoutId,
        ),
      ),
    );
    await settle(tester);
  }

  Future<Workout?> stored(WidgetTester tester, String workoutId) async {
    final workout = await tester.runAsync(
      () => harness.repository.readWorkout(workoutId),
    );
    return workout;
  }

  Future<void> enter(WidgetTester tester, int index, String text) async {
    await tester.enterText(_field(index), text);
    await settle(tester);
  }

  testWidgets('Satz 102,5 × 8 wird eingetragen und gespeichert', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await enter(tester, 0, '102,5');
    await enter(tester, 1, '8');

    final set = (await stored(tester, id))!.exercises.single.sets.single;
    expect(set.weightKg, 102.5);
    expect(set.repetitions, 8);
    expect(_labelled('Übung vollständig'), findsOneWidget);
  });

  testWidgets('ungültige Wiederholungen werden markiert ohne zu speichern', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 80, repetitions: 5),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await enter(tester, 1, '1,5');

    expect(find.text('Nur ganze Zahlen'), findsOneWidget);
    final set = (await stored(tester, id))!.exercises.single.sets.single;
    expect(set.repetitions, 5);
    expect(set.weightKg, 80);
  });

  testWidgets('Eingabe mit abgebrochenem Prozess bleibt erhalten', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 60),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await enter(tester, 1, '8');

    // Ein neues Repository auf derselben Datenbank entspricht einem Neustart.
    final restarted = TrainingLogRepository(
      store: harness.store,
      catalog: harness.repository.catalog,
    );
    final workout = await tester.runAsync(() => restarted.readWorkout(id));
    final set = workout!.exercises.single.sets.single;
    expect(set.repetitions, 8);
    expect(set.weightKg, 60);
  });

  testWidgets(
    'Klimmzug ohne Zusatzgewicht gilt mit Wiederholungen als erfasst',
    (tester) async {
      final id = await seedActive(
        tester,
        blocks: [
          _block('b1', 'pull', 'Klimmzug', ExerciseKind.bodyweightLoaded, [
            const LoggedSet(setId: 's1'),
          ]),
        ],
      );
      await pumpWorkout(tester, id);
      expect(_labelled('Übung vollständig'), findsNothing);

      await enter(tester, 1, '10');

      expect(_labelled('Übung vollständig'), findsOneWidget);
      final set = (await stored(tester, id))!.exercises.single.sets.single;
      expect(set.weightKg, isNull);
      expect(set.repetitions, 10);
    },
  );

  testWidgets('blasse Vorwerte zählen nicht als erfasst', (tester) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push A',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _block('old', 'bench', 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
          ]),
        ],
      ),
    );
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    expect(find.text('100'), findsOneWidget);
    expect(_labelled('Übung vollständig'), findsNothing);
  });

  testWidgets(
    'Platzhalter zeigen Vorwerte blass und werden nicht gespeichert',
    (tester) async {
      await tester.runAsync(
        () => harness.seedWorkout(
          title: 'Push A',
          start: DateTime.utc(2026, 10, 10, 8),
          end: DateTime.utc(2026, 10, 10, 9),
          blocks: [
            _block('old', 'bench', 'Bankdrücken', ExerciseKind.strength, [
              const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
              const LoggedSet(setId: 'o2', weightKg: 100, repetitions: 7),
            ]),
          ],
        ),
      );
      final id = await seedActive(
        tester,
        blocks: [
          _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 's1'),
            const LoggedSet(setId: 's2'),
          ]),
        ],
      );
      await pumpWorkout(tester, id);

      final colors = GainerColors.light;
      expect(find.text('100'), findsNWidgets(2));
      expect(find.text('8'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      final placeholder = tester.widget<Text>(find.text('100').first);
      expect(placeholder.style?.color, colors.placeholderText);
      final set = (await stored(tester, id))!.exercises.single.sets.first;
      expect(set.weightKg, isNull);
      expect(set.repetitions, isNull);
    },
  );

  testWidgets('Vorwert-Semantik: Platzhalter als Vorwert angesagt', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push A',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _block('old', 'bench', 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
          ]),
        ],
      ),
    );
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    final values = _semanticsValues(
      tester.getSemantics(find.byType(WorkoutScreen)),
    ).toList();
    expect(values, contains('Vorwert 100'));
    handle.dispose();
  });

  testWidgets('Tipp auf das Satzlabel übernimmt den Vorwert', (tester) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Push A',
        start: DateTime.utc(2026, 10, 10, 8),
        end: DateTime.utc(2026, 10, 10, 9),
        blocks: [
          _block('old', 'bench', 'Bankdrücken', ExerciseKind.strength, [
            const LoggedSet(setId: 'o1', weightKg: 100, repetitions: 8),
          ]),
        ],
      ),
    );
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Satz 1, Vorwert übernehmen'));
    await settle(tester);

    final set = (await stored(tester, id))!.exercises.single.sets.single;
    expect(set.weightKg, 100);
    expect(set.repetitions, 8);
  });

  testWidgets('ohne Vorwerte bleiben die Felder leer', (tester) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    expect(_text(tester, 0), isEmpty);
    expect(_text(tester, 1), isEmpty);
    expect(find.text('100'), findsNothing);
  });

  testWidgets('Nummerierung ist W, 1, D, 2', (tester) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', setType: SetType.warmup),
          const LoggedSet(setId: 's2'),
          const LoggedSet(setId: 's3', setType: SetType.dropset),
          const LoggedSet(setId: 's4'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    for (final label in ['W', '1', 'D', '2']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Satz duplizieren kopiert die Werte direkt dahinter', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 50, repetitions: 10),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Satzmenü'));
    await settle(tester);
    await tester.tap(find.text('Duplizieren'));
    await settle(tester);

    final sets = (await stored(tester, id))!.exercises.single.sets;
    expect(sets, hasLength(2));
    expect(sets[1].setId, isNot('s1'));
    expect(sets[1].weightKg, 50);
    expect(sets[1].repetitions, 10);
  });

  testWidgets('letzten Satz entfernen lässt den Block bestehen', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Satzmenü'));
    await settle(tester);
    await tester.tap(find.text('Entfernen'));
    await settle(tester);

    final block = (await stored(tester, id))!.exercises.single;
    expect(block.exerciseNameSnapshot, 'Bankdrücken');
    expect(block.sets, isEmpty);
    expect(find.text('Noch keine Sätze.'), findsOneWidget);
  });

  testWidgets('RIR ausgeblendet behält den gespeicherten Wert', (tester) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1', weightKg: 80, repetitions: 5, rir: 2),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    expect(find.text('RIR'), findsNothing);
    expect((await stored(tester, id))!.exercises.single.sets.single.rir, 2);

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('RIR anzeigen'));
    await settle(tester);
    expect(find.text('RIR'), findsOneWidget);
    expect(_text(tester, 2), '2');

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('RIR ausblenden'));
    await settle(tester);
    expect(find.text('RIR'), findsNothing);
    expect((await stored(tester, id))!.exercises.single.sets.single.rir, 2);
  });

  testWidgets('Eingabe in lbs speichert etwa 102,06 kg und zeigt 225', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Weitere Aktionen'));
    await settle(tester);
    await tester.tap(find.text('Gewichtseinheit: kg'));
    await settle(tester);
    await enter(tester, 0, '225');

    final set = (await stored(tester, id))!.exercises.single.sets.single;
    expect(set.weightKg, closeTo(102.06, 0.01));
    expect(_text(tester, 0), '225');
    expect(find.text('Lbs'), findsOneWidget);
  });

  testWidgets('weiter springt von Kg über Wdh. zum Kg des nächsten Satzes', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'bench', 'Bankdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
          const LoggedSet(setId: 's2'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_field(0));
    await settle(tester);
    await enter(tester, 0, '100');
    await tester.tap(_labelled('Weiter'));
    await settle(tester);

    expect(_hasFocus(tester, 1), isTrue);
    await enter(tester, 1, '6');
    await tester.tap(_labelled('Weiter'));
    await settle(tester);

    expect(_hasFocus(tester, 2), isTrue);
    final sets = (await stored(tester, id))!.exercises.single.sets;
    expect(sets.first.repetitions, 6);
    expect(sets.first.weightKg, 100);
  });

  testWidgets('Superset zeigt die Buchstaben A und B', (tester) async {
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'curl', 'Bizepscurl', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ], supersetId: 'ss'),
        _block('b2', 'triceps', 'Trizepsdrücken', ExerciseKind.strength, [
          const LoggedSet(setId: 's2'),
        ], supersetId: 'ss'),
      ],
    );
    await pumpWorkout(tester, id);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('Bizepscurl'), findsOneWidget);
    expect(find.text('Trizepsdrücken'), findsOneWidget);
  });

  testWidgets('Verlauf zeigt nur erfasste Sätze früherer Trainings', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Alt',
        start: DateTime.utc(2026, 10, 1, 8),
        end: DateTime.utc(2026, 10, 1, 9),
        blocks: [
          _block('a', 'row', 'Rudern', ExerciseKind.strength, [
            const LoggedSet(setId: 'a1'),
          ]),
        ],
      ),
    );
    await tester.runAsync(
      () => harness.seedWorkout(
        title: 'Zug',
        start: DateTime.utc(2026, 10, 9, 8),
        end: DateTime.utc(2026, 10, 9, 9),
        blocks: [
          _block('z', 'row', 'Rudern', ExerciseKind.strength, [
            const LoggedSet(setId: 'z1'),
            const LoggedSet(setId: 'z2', weightKg: 60, repetitions: 10),
          ]),
        ],
      ),
    );
    final id = await seedActive(
      tester,
      blocks: [
        _block('b1', 'row', 'Rudern', ExerciseKind.strength, [
          const LoggedSet(setId: 's1'),
        ]),
      ],
    );
    await pumpWorkout(tester, id);

    await tester.tap(_labelled('Verlauf'));
    await settle(tester);

    expect(find.byType(ExerciseStatisticsScreen), findsOneWidget);
    expect(find.text('Zug'), findsOneWidget);
    expect(find.text('Alt'), findsNothing);
  });

  testWidgets('Startzeit ändern übernimmt die neue Zeit', (tester) async {
    final id = await seedActive(
      tester,
      title: 'Legs 2',
      start: DateTime(2026, 10, 15, 18).toUtc(),
      end: DateTime(2026, 10, 15, 19).toUtc(),
    );
    await pumpWorkout(tester, id);

    await tester.tap(find.text('Startzeit'));
    await settle(tester);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    picker.onDateTimeChanged(DateTime(2026, 10, 15, 17, 41));
    await tester.pump();
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final workout = await stored(tester, id);
    expect(workout!.startedAtUtc, DateTime(2026, 10, 15, 17, 41).toUtc());
    expect(
      find.text(formatWorkoutDateTime(DateTime(2026, 10, 15, 17, 41))),
      findsOneWidget,
    );
  });

  testWidgets('Startzeit ohne Bewegen des Wählers behält die Sekunden', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 15, 17, 41, 35).toUtc();
    final id = await seedActive(
      tester,
      title: 'Legs 2',
      start: start,
      end: DateTime(2026, 10, 15, 19).toUtc(),
    );
    await pumpWorkout(tester, id);

    await tester.tap(find.text('Startzeit'));
    await settle(tester);
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final workout = await stored(tester, id);
    expect(workout!.startedAtUtc, start);
  });

  testWidgets(
    'Endzeit eines sehr kurzen Trainings erlaubt Fertig unverändert',
    (tester) async {
      final start = DateTime(2026, 10, 15, 17, 41, 10).toUtc();
      final end = DateTime(2026, 10, 15, 17, 41, 50).toUtc();
      final id = await seedActive(tester, start: start, end: end);
      await pumpWorkout(tester, id);

      await tester.tap(find.text('Endzeit'));
      await settle(tester);
      expect(
        find.text('Die Endzeit muss nach der Startzeit liegen.'),
        findsNothing,
      );
      await tester.tap(find.text('Fertig'));
      await settle(tester);

      expect(find.byType(CupertinoDatePicker), findsNothing);
      final workout = await stored(tester, id);
      expect(workout!.endedAtUtc, end);
    },
  );

  testWidgets('Wähler eine Minute weiter und zurück lässt die Endzeit stehen', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 15, 17, 41, 10).toUtc();
    final end = DateTime(2026, 10, 15, 17, 41, 50).toUtc();
    final id = await seedActive(tester, start: start, end: end);
    await pumpWorkout(tester, id);

    await tester.tap(find.text('Endzeit'));
    await settle(tester);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    picker.onDateTimeChanged(DateTime(2026, 10, 15, 17, 42));
    await tester.pump();
    picker.onDateTimeChanged(DateTime(2026, 10, 15, 17, 41));
    await tester.pump();
    expect(
      find.text('Die Endzeit muss nach der Startzeit liegen.'),
      findsNothing,
    );
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    expect(find.byType(CupertinoDatePicker), findsNothing);
    final workout = await stored(tester, id);
    expect(workout!.endedAtUtc, end);
  });

  testWidgets('ungültige Endzeit zeigt Feldfehler und lässt den Stand', (
    tester,
  ) async {
    final id = await seedActive(
      tester,
      title: 'Legs 2',
      start: DateTime(2026, 10, 15, 18).toUtc(),
      end: DateTime(2026, 10, 15, 19).toUtc(),
    );
    await pumpWorkout(tester, id);

    await tester.tap(find.text('Endzeit'));
    await settle(tester);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    picker.onDateTimeChanged(DateTime(2026, 10, 15, 17, 30));
    await tester.pump();

    expect(
      find.text('Die Endzeit muss nach der Startzeit liegen.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Fertig'));
    await settle(tester);

    final workout = await stored(tester, id);
    expect(workout!.endedAtUtc, DateTime(2026, 10, 15, 19).toUtc());
  });
}
