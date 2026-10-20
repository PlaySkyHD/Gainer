import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/training/muscle_suggestion_service.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/domain/models/training/muscle_ai.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

import 'muscle_map_test_support.dart';
import 'training_plans_test_support.dart';
import 'training_test_support.dart';

class _FakeService implements MuscleSuggestionService {
  _FakeService(this.replies);

  final List<Object> replies;
  final calls = <List<MuscleAiTurn>>[];
  final names = <String>[];

  @override
  Future<MuscleAiReply> suggest({
    required String name,
    required ExerciseKind kind,
    String? notes,
    List<MuscleAiTurn> turns = const [],
  }) async {
    names.add(name);
    calls.add(turns);
    final next = replies.removeAt(0);
    if (next is MuscleAiReply) return next;
    throw next;
  }
}

String _value(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .last
    .data!;

void main() {
  Future<TrainingHarness> harnessWith(
    WidgetTester tester,
    MuscleSuggestionService service,
  ) async {
    final harness = await tester.runAsync(
      () => TrainingHarness.create(muscleSuggestions: service),
    );
    addTearDown(() => tester.runAsync(harness!.dispose));
    return harness!;
  }

  Future<void> openAi(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('exercise-muscle-ai'));
    await scrollIntoView(tester, button);
    await tester.tap(button);
    await settle(tester);
  }

  testWidgets('KI fragt nach und der Vorschlag wird übernommen', (
    tester,
  ) async {
    final service = _FakeService([
      const MuscleAiQuestion(
        question: 'Welcher Griff?',
        options: ['Eng', 'Weit'],
      ),
      const MuscleAiSuggestion(
        primary: [Muscle.lats],
        secondary: [Muscle.biceps, Muscle.rearDelts],
        explanation: 'Enger Griff betont den Latissimus.',
      ),
    ]);
    final harness = await harnessWith(tester, service);
    final exercise = await tester.runAsync(
      () => seedExercise(harness, name: 'Rudern Maschine'),
    );
    await openEditorFor(tester, harness, exercise!);

    await openAi(tester);
    expect(find.text('Welcher Griff?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('muscle-ai-option-0')));
    await settle(tester);

    expect(service.names, ['Rudern Maschine', 'Rudern Maschine']);
    expect(service.calls.last.single.answer, 'Eng');
    expect(_value(tester, 'muscle-ai-primary'), 'Latissimus');
    expect(find.text('Enger Griff betont den Latissimus.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('muscle-ai-apply')));
    await settle(tester);

    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-secondary-muscles')),
    );
    expect(_value(tester, 'exercise-primary-muscles'), 'Latissimus');
    expect(
      _value(tester, 'exercise-secondary-muscles'),
      'Bizeps, Hintere Schulter',
    );
  });

  testWidgets('Tageslimit zeigt eine verständliche Meldung', (tester) async {
    final service = _FakeService([
      const ApiException(
        statusCode: 429,
        code: 'daily_budget_exhausted',
        message: 'exhausted',
      ),
      const MuscleAiSuggestion(
        primary: [Muscle.chest],
        secondary: [],
        explanation: 'Brust.',
      ),
    ]);
    final harness = await harnessWith(tester, service);
    final exercise = await tester.runAsync(
      () => seedExercise(harness, name: 'Brustpresse'),
    );
    await openEditorFor(tester, harness, exercise!);

    await openAi(tester);

    expect(
      find.text(
        'Das Tageslimit für KI-Anfragen ist erreicht. Morgen geht es wieder.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('muscle-ai-retry')));
    await settle(tester);
    expect(_value(tester, 'muscle-ai-primary'), 'Brust');
  });

  testWidgets('ohne KI-Dienst fehlt der Button', (tester) async {
    final harness = await tester.runAsync(TrainingHarness.create);
    addTearDown(() => tester.runAsync(harness!.dispose));
    final exercise = await tester.runAsync(
      () => seedExercise(harness!, name: 'Brustpresse'),
    );
    await openEditorFor(tester, harness!, exercise!);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('exercise-primary-muscles')),
    );

    expect(find.byKey(const ValueKey('exercise-muscle-ai')), findsNothing);
  });
}
