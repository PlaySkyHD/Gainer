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
    FakeCoachMemoryRepository? memories,
    bool online = true,
  }) async {
    final api = CoachTestApi(
      (_) async => coachAnswer(memorySuggestions: suggestions),
    );
    final repository = memories ?? FakeCoachMemoryRepository();
    final model = CoachViewModel(
      CoachRepository(api),
      memories: repository,
      online: online,
    );
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
    // Nur gelesen, um ein volles Gedächtnis zu erkennen.
    expect(repository.calls, ['list']);
    expect(find.byKey(const ValueKey('coach-remember-blocked')), findsNothing);
  });

  testWidgets('remember stores the suggestion and marks it as saved', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    // Nach dem Merken zählt die Liste neu, solange Vorschläge offen sind.
    expect(repository.calls, [
      'list',
      'create goal Halbmarathon im Mai',
      'list',
    ]);
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
    expect(
      repository.calls.where((call) => call.startsWith('create')),
      hasLength(1),
    );
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
    expect(repository.calls, ['list']);
  });

  bool rememberEnabled(WidgetTester tester) =>
      tester
          .widget<GainerPillButton>(
            find.widgetWithText(GainerPillButton, 'Merken').first,
          )
          .onPressed !=
      null;

  String? blockedReason(WidgetTester tester) {
    final finder = find.byKey(const ValueKey('coach-remember-blocked'));
    return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
  }

  testWidgets('other failures explain the reason at the suggestion', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);
    repository.failWith = serverError;

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Das hat nicht geklappt. Versuche es erneut.'),
      findsOneWidget,
    );
    expect(rememberEnabled(tester), isTrue);

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.textContaining('nicht geklappt'), findsNothing);
  });

  testWidgets('lost connection locks remember, names it and offers a retry', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);
    repository.failWith = networkError;

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    expect(
      blockedReason(tester),
      'Keine Verbindung. „Merken“ geht erst wieder online.',
    );
    expect(rememberEnabled(tester), isFalse);
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.startsWith('create')), [
      'create goal Halbmarathon im Mai',
    ]);
    // „Verwerfen“ bleibt möglich.
    expect(
      tester
          .widget<GainerPillButton>(
            find.widgetWithText(GainerPillButton, 'Verwerfen').first,
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('coach-remember-retry')));
    await tester.pumpAndSettle();
    expect(blockedReason(tester), isNull);
    expect(find.byKey(const ValueKey('coach-remember-retry')), findsNothing);
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(find.text('Gemerkt'), findsOneWidget);
  });

  testWidgets('without connection while reading the memory remember is off', (
    tester,
  ) async {
    final repository = FakeCoachMemoryRepository()..failListWith = networkError;
    await askWithSuggestions(tester, memories: repository, online: false);

    expect(rememberEnabled(tester), isFalse);
    expect(blockedReason(tester), contains('Keine Verbindung'));
  });

  testWidgets('a full memory locks remember until a note is deleted', (
    tester,
  ) async {
    final repository = FakeCoachMemoryRepository([
      for (var i = 0; i < 50; i++)
        memoryItem(
          '22222222-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          CoachMemoryCategory.other,
          'Notiz $i',
        ),
    ]);
    await askWithSuggestions(tester, memories: repository);

    expect(rememberEnabled(tester), isFalse);
    expect(blockedReason(tester), startsWith('Das Gedächtnis ist voll.'));

    // Auf einem anderen Gerät gelöscht; nach dem Gedächtnis-Screen stimmt
    // die Belegung wieder.
    repository.items.removeLast();
    await tester.tap(find.bySemanticsLabel('Gedächtnis'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();

    expect(blockedReason(tester), isNull);
    expect(rememberEnabled(tester), isTrue);
  });

  testWidgets('memory_limit_reached locks remember and the last free slot '
      'fills it', (tester) async {
    final repository = FakeCoachMemoryRepository([
      for (var i = 0; i < 49; i++)
        memoryItem(
          '22222222-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          CoachMemoryCategory.other,
          'Notiz $i',
        ),
    ]);
    final (_, model) = await askWithSuggestions(tester, memories: repository);

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(model.memoryFull, isTrue);
    expect(rememberEnabled(tester), isFalse);

    // Der Server meldet voll, obwohl die Liste noch Platz zeigte.
    final (other, _) = await askWithSuggestions(tester);
    other.failWith = limitReached;
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(blockedReason(tester), startsWith('Das Gedächtnis ist voll.'));
    expect(find.text('Gemerkt'), findsNothing);
  });

  List<ApiCoachMemory> notes(int count) => [
    for (var i = 0; i < count; i++)
      memoryItem(
        '22222222-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        CoachMemoryCategory.other,
        'Notiz $i',
      ),
  ];

  testWidgets('remembering a text that is already stored does not count '
      'twice at 49 of 50', (tester) async {
    final repository = FakeCoachMemoryRepository([
      ...notes(48),
      memoryItem(
        '33333333-0000-4000-8000-000000000001',
        CoachMemoryCategory.other,
        'Halbmarathon im Mai',
      ),
    ])..createReturnsExisting = true;
    final (_, model) = await askWithSuggestions(tester, memories: repository);

    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();

    // Der Server gab den vorhandenen Eintrag zurück: weiter 49 von 50.
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(repository.items, hasLength(49));
    expect(model.memoryFull, isFalse);
    expect(rememberEnabled(tester), isTrue);
    expect(blockedReason(tester), isNull);
  });

  test('an older usage read never overwrites a newer one', () async {
    final api = CoachTestApi(
      (_) async => coachAnswer(
        memorySuggestions: const [
          ApiCoachMemorySuggestion(
            category: CoachMemoryCategory.goal,
            text: 'Halbmarathon im Mai',
          ),
          ApiCoachMemorySuggestion(
            category: CoachMemoryCategory.other,
            text: 'Trainiert morgens',
          ),
        ],
      ),
    );
    final repository = FakeCoachMemoryRepository(notes(49));
    final model = CoachViewModel(CoachRepository(api), memories: repository);
    final afterAnswer = Completer<void>();
    final afterRemember = Completer<void>();
    repository.listGates.addAll([afterAnswer, afterRemember]);

    // Die Belegung nach der Antwort liest noch 49 und hängt.
    final asking = model.ask('Frage');
    await pumpEventQueue();
    expect(model.response, isNotNull);

    // Das Merken füllt das Gedächtnis; sein Lesevorgang sieht 50.
    final remembering = model.remember(0);
    await pumpEventQueue();
    afterRemember.complete();
    await remembering;
    expect(model.memoryFull, isTrue);

    // Die ältere Antwort kommt zuletzt und wird verworfen.
    afterAnswer.complete();
    await asking;
    expect(model.memoryFull, isTrue);
    expect(model.rememberBlockedReason, startsWith('Das Gedächtnis ist voll.'));
    model.dispose();
    api.close();
  });

  testWidgets('the memory screen opens with the current connection state', (
    tester,
  ) async {
    // Beim Öffnen des Kontos offline, inzwischen hat der Coach geantwortet.
    final (repository, model) = await askWithSuggestions(tester, online: false);
    expect(model.memoryOffline, isFalse);

    await tester.tap(find.bySemanticsLabel('Gedächtnis'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['list', 'list']);
    expect(find.text('Erneut laden'), findsNothing);
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await tester.pumpAndSettle();

    // Jetzt geht die Verbindung verloren: Der Screen lädt nicht von selbst.
    repository.failWith = networkError;
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(model.memoryOffline, isTrue);
    final before = repository.calls.length;
    await tester.tap(find.bySemanticsLabel('Gedächtnis'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(before));
    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
  });

  testWidgets('block reason and retry disappear without open suggestions', (
    tester,
  ) async {
    final (repository, _) = await askWithSuggestions(tester);
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    repository.failWith = networkError;
    await tester.tap(find.text('Merken').first);
    await tester.pumpAndSettle();
    expect(blockedReason(tester), isNotNull);
    expect(find.byKey(const ValueKey('coach-remember-retry')), findsOneWidget);

    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();

    // Nur noch der gemerkte Vorschlag: nichts mehr zu sperren.
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(blockedReason(tester), isNull);
    expect(find.byKey(const ValueKey('coach-remember-retry')), findsNothing);
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
