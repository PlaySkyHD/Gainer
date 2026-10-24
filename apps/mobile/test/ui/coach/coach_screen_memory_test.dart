import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/coach/coach_memory_screen.dart';
import 'package:gainer_mobile/ui/features/coach/coach_screen.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';

import 'coach_memory_fakes.dart';

void main() {
  Future<(FakeCoachMemoryRepository, CoachViewModel)> askWithSuggestions(
    WidgetTester tester, {
    List<ApiCoachMemorySuggestion> suggestions = const [
      ApiCoachMemorySuggestion(
        category: CoachMemoryCategory.goal,
        text: 'Halbmarathon im Mai',
      ),
      ApiCoachMemorySuggestion(
        category: CoachMemoryCategory.intolerance,
        text: 'Laktoseintoleranz',
      ),
    ],
    double textScale = 1,
  }) async {
    final api = CoachTestApi(
      (_) async => coachAnswer(memorySuggestions: suggestions),
    );
    final repository = FakeCoachMemoryRepository();
    final model = CoachViewModel(CoachRepository(api), memories: repository);
    addTearDown(model.dispose);
    addTearDown(api.close);
    await pumpCoachApp(
      tester,
      CoachScreen(viewModel: model),
      textScale: textScale,
      size: const Size(390, 1400),
    );
    await tester.enterText(
      find.byType(CupertinoTextField),
      'Ich laufe im Mai einen Halbmarathon.',
    );
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();
    return (repository, model);
  }

  testWidgets('suggestions appear under the answer and nothing is stored', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);

    expect(find.text('Merken?'), findsOneWidget);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
    expect(find.text('Ziel'), findsOneWidget);
    expect(find.text('Unverträglichkeit'), findsOneWidget);
    expect(find.text('Merken'), findsNWidgets(2));
    expect(find.text('Verwerfen'), findsNWidgets(2));
    expect(find.textContaining('speichert nichts von selbst'), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  testWidgets('remember stores the suggestion and marks it as saved', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    expect(repository.calls, ['create goal Halbmarathon im Mai']);
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.text('Merken'), findsOneWidget);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
  });

  testWidgets('remember shows a spinner while saving and ignores repeats', (
    tester,
  ) async {
    final (repository, model) = await askWithSuggestions(tester);
    repository.createGate = Completer<void>();

    await tester.tap(find.text('Merken').first);
    await tester.pump();
    expect(model.suggestionState(0), CoachSuggestionState.saving);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await model.remember(0);
    final dismiss = tester.widget<GainerPillButton>(
      find.widgetWithText(GainerPillButton, 'Verwerfen').first,
    );
    expect(dismiss.onPressed, isNull);

    repository.createGate!.complete();
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(1));
    expect(find.text('Gemerkt'), findsOneWidget);
  });

  testWidgets('dismiss hides the suggestion without storing it', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);

    await tester.tap(find.text('Verwerfen').last);
    await tester.pumpAndSettle();

    expect(find.text('Laktoseintoleranz'), findsNothing);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('Merken?'), findsNothing);
    expect(repository.calls, isEmpty);
  });

  testWidgets('failed remember explains the reason and allows a retry', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);
    repository.failWith = limitReached;

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Das Gedächtnis ist voll. Lösche zuerst eine Notiz.'),
      findsOneWidget,
    );
    expect(find.text('Gemerkt'), findsNothing);

    repository.failWith = networkError;
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Keine Verbindung. Das Gedächtnis lässt sich nur online ändern.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.textContaining('Keine Verbindung'), findsNothing);
  });

  testWidgets('a new question resets the suggestion states', (tester) async {
    final (_, model) = await askWithSuggestions(tester);
    model.dismiss(1);
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(model.suggestionState(0), CoachSuggestionState.open);
    expect(model.suggestionState(1), CoachSuggestionState.open);
    expect(find.text('Merken'), findsNWidgets(2));
  });

  testWidgets('toolbar opens the memory screen', (tester) async {
    final (repository, _) = await askWithSuggestions(tester);
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Gedächtnis'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachMemoryScreen), findsOneWidget);
    expect(repository.calls.last, 'list');
    expect(find.text('Ziele'), findsOneWidget);

    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CoachMemoryScreen), findsNothing);
  });

  testWidgets('coach without a memory repository shows no memory controls', (
    tester,
  ) async {
    final api = CoachTestApi(
      (_) async => coachAnswer(
        memorySuggestions: const [
          ApiCoachMemorySuggestion(
            category: CoachMemoryCategory.other,
            text: 'Etwas',
          ),
        ],
      ),
    );
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);
    await pumpCoachApp(tester, CoachScreen(viewModel: model));
    await tester.enterText(find.byType(CupertinoTextField), 'Frage');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Gedächtnis'), findsNothing);
    expect(find.text('Merken?'), findsNothing);
    await model.remember(0);
    expect(model.suggestionState(0), CoachSuggestionState.open);
  });

  testWidgets('text size 2 keeps suggestions readable without overflow', (
    tester,
  ) async {
    await askWithSuggestions(tester, textScale: 2);
    await tester.scrollUntilVisible(
      find.text('Verwerfen').last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Merken').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('remember ignores invalid indexes', () async {
    final api = CoachTestApi((_) async => coachAnswer());
    final repository = FakeCoachMemoryRepository();
    final model = CoachViewModel(CoachRepository(api), memories: repository);
    await model.remember(0);
    await model.ask('Frage');
    await model.remember(-1);
    await model.remember(5);
    expect(repository.calls, isEmpty);
    model.dispose();
    model.dismiss(0);
    await model.remember(0);
    api.close();
  });
}

ApiCoachResponse coachAnswer({
  List<ApiCoachMemorySuggestion> memorySuggestions = const [],
}) => ApiCoachResponse(
  summary: 'Dein Training ist konstant.',
  observations: const ['Drei Einheiten pro Woche.'],
  dataGaps: const [],
  suggestions: const [],
  asOfRevision: 9,
  memorySuggestions: memorySuggestions,
);

class CoachTestApi extends ApiClient {
  CoachTestApi(this.onAsk)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Future<ApiCoachResponse> Function(String question) onAsk;

  @override
  Future<ApiCoachResponse> askCoach(String question) => onAsk(question);
}
