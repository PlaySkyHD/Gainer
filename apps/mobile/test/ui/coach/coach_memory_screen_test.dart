import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/coach/coach_memory_screen.dart';
import 'package:gainer_mobile/ui/features/coach/coach_memory_view_model.dart';

import 'coach_memory_fakes.dart';

void main() {
  Future<FakeCoachMemoryRepository> pumpMemory(
    WidgetTester tester, {
    List<ApiCoachMemory>? items,
    FakeCoachMemoryRepository? repository,
    bool online = true,
    double textScale = 1,
    Size size = const Size(390, 1000),
  }) async {
    final memories =
        repository ?? FakeCoachMemoryRepository(items ?? sampleMemories());
    await pumpCoachApp(
      tester,
      CoachMemoryScreen(repository: memories, online: online),
      textScale: textScale,
      size: size,
    );
    return memories;
  }

  Finder editorError() =>
      find.byKey(const ValueKey('coach-memory-editor-error'));

  String fieldText(WidgetTester tester) => tester
      .widget<CupertinoTextField>(
        find.byKey(const ValueKey('coach-memory-text')),
      )
      .controller!
      .text;

  bool addEnabled(WidgetTester tester) =>
      tester
          .widget<GainerToolbarButton>(
            find.byKey(const ValueKey('coach-memory-add')),
          )
          .onPressed !=
      null;

  testWidgets('lists notes grouped by category with usage and hint', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);

    expect(repository.calls, ['list']);
    expect(find.text('Gedächtnis'), findsWidgets);
    for (final header in [
      'Ziele',
      'Vorlieben',
      'Unverträglichkeiten',
      'Verletzungen',
    ]) {
      expect(find.text(header), findsOneWidget);
    }
    expect(find.text('Sonstiges'), findsNothing);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
    expect(find.textContaining('4 von 50 Notizen.'), findsOneWidget);
    expect(find.textContaining('nicht als Anweisungen'), findsOneWidget);
    // Feste Reihenfolge: Ziele vor Vorlieben vor Unverträglichkeiten.
    expect(
      tester.getTopLeft(find.text('Ziele')).dy,
      lessThan(tester.getTopLeft(find.text('Vorlieben')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Vorlieben')).dy,
      lessThan(tester.getTopLeft(find.text('Unverträglichkeiten')).dy),
    );
    expect(addEnabled(tester), isTrue);
  });

  testWidgets('empty memory explains how notes are created', (tester) async {
    await pumpMemory(tester, items: const []);

    expect(find.textContaining('Noch keine Notizen.'), findsOneWidget);
    expect(find.textContaining('0 von 50 Notizen.'), findsOneWidget);
    expect(find.text('Alles vergessen'), findsNothing);
  });

  testWidgets('adding a note opens the sheet and stores the note', (
    tester,
  ) async {
    final repository = await pumpMemory(tester, items: const []);

    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Notiz'), findsOneWidget);
    final save = find.byKey(const ValueKey('coach-memory-save'));
    expect(tester.widget<GainerPillButton>(save).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      '  Keine Nüsse  ',
    );
    await tester.tap(
      find.byKey(const ValueKey('coach-memory-category-intolerance')),
    );
    await tester.pumpAndSettle();
    expect(find.text('11 von 200 Zeichen'), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.calls.last, 'create intolerance Keine Nüsse');
    expect(find.text('Neue Notiz'), findsNothing);
    expect(find.text('Unverträglichkeiten'), findsOneWidget);
    expect(find.text('Keine Nüsse'), findsOneWidget);
  });

  testWidgets('tapping a note edits text and category', (tester) async {
    final repository = await pumpMemory(tester);

    await tester.tap(find.text('Halbmarathon im Mai'));
    await tester.pumpAndSettle();
    expect(find.text('Notiz bearbeiten'), findsOneWidget);
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('coach-memory-text')),
    );
    expect(field.controller!.text, 'Halbmarathon im Mai');

    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Marathon im Oktober',
    );
    await tester.tap(find.byKey(const ValueKey('coach-memory-category-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();

    expect(
      repository.calls.last,
      'update 11111111-0000-4000-8000-000000000001 other Marathon im Oktober',
    );
    expect(repository.baseVersions, [1]);
    expect(find.text('Notiz bearbeiten'), findsNothing);
    expect(find.text('Marathon im Oktober'), findsOneWidget);
    expect(find.text('Halbmarathon im Mai'), findsNothing);
    expect(find.text('Sonstiges'), findsOneWidget);
    expect(find.text('Ziele'), findsNothing);
  });

  testWidgets('closing the sheet without saving changes nothing', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);

    await tester.tap(find.text('Laktoseintoleranz'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Schließen'));
    await tester.pumpAndSettle();

    expect(repository.calls, ['list']);
  });

  testWidgets('swipe deletes a note only after confirmation', (tester) async {
    final repository = await pumpMemory(tester);

    await tester.drag(find.text('Laktoseintoleranz'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Notiz löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Laktoseintoleranz'), findsOneWidget);
    expect(repository.calls, ['list']);

    await tester.drag(find.text('Laktoseintoleranz'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();

    expect(
      repository.calls.last,
      'delete 11111111-0000-4000-8000-000000000002',
    );
    expect(find.text('Laktoseintoleranz'), findsNothing);
    expect(find.text('Unverträglichkeiten'), findsNothing);
    expect(find.textContaining('3 von 50 Notizen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed delete keeps the note and explains why', (tester) async {
    final repository = await pumpMemory(tester);
    repository.failWith = const ApiException(
      statusCode: 500,
      code: 'server_error',
      message: 'boom',
    );

    await tester.drag(find.text('Laktoseintoleranz'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();

    expect(find.text('Laktoseintoleranz'), findsOneWidget);
    expect(
      find.text('Das hat nicht geklappt. Versuche es erneut.'),
      findsOneWidget,
    );
  });

  testWidgets('forget all asks first and then empties the memory', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);

    await tester.tap(find.byKey(const ValueKey('coach-memory-forget-all')));
    await tester.pumpAndSettle();
    expect(find.text('Alles vergessen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['list']);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coach-memory-forget-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alles vergessen').last);
    await tester.pumpAndSettle();

    expect(repository.calls.last, 'deleteAll');
    expect(find.text('Halbmarathon im Mai'), findsNothing);
    expect(find.textContaining('Noch keine Notizen.'), findsOneWidget);
  });

  testWidgets('offline account locks changes and names the reason', (
    tester,
  ) async {
    final repository = await pumpMemory(tester, online: false);

    expect(repository.calls, isEmpty);
    expect(
      find.text(
        'Keine Verbindung. Dein Gedächtnis lässt sich nur online ansehen und '
        'ändern.',
      ),
      findsOneWidget,
    );
    expect(addEnabled(tester), isFalse);
    expect(find.text('Alles vergessen'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('coach-memory-reload')));
    await tester.pumpAndSettle();

    expect(repository.calls, ['list']);
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
    expect(addEnabled(tester), isTrue);
  });

  testWidgets('losing the connection during a change locks editing', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);
    repository.failWith = networkError;

    await tester.tap(find.byKey(const ValueKey('coach-memory-forget-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alles vergessen').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Keine Verbindung. Das Gedächtnis lässt sich nur online ändern.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Keine Verbindung. Änderungen sind erst wieder online möglich.',
      ),
      findsOneWidget,
    );
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
    expect(addEnabled(tester), isFalse);
    expect(
      tester
          .widget<GainerPillButton>(
            find.byKey(const ValueKey('coach-memory-forget-all')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(GainerSwipeToDelete), findsNothing);

    await tester.tap(find.text('Halbmarathon im Mai'));
    await tester.pumpAndSettle();
    expect(find.text('Notiz bearbeiten'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('coach-memory-reload')));
    await tester.pumpAndSettle();
    expect(addEnabled(tester), isTrue);
    expect(find.byType(GainerSwipeToDelete), findsNWidgets(4));
  });

  testWidgets('server error on load offers a retry', (tester) async {
    final repository = FakeCoachMemoryRepository(sampleMemories())
      ..failListWith = serverError;
    await pumpMemory(tester, repository: repository);

    expect(
      find.text(
        'Das Gedächtnis konnte nicht geladen werden. Versuche es erneut.',
      ),
      findsOneWidget,
    );
    expect(addEnabled(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('coach-memory-reload')));
    await tester.pumpAndSettle();
    expect(find.text('Halbmarathon im Mai'), findsOneWidget);
  });

  testWidgets('full memory disables adding and says how to make room', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 50; i++)
        memoryItem(
          '22222222-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          CoachMemoryCategory.other,
          'Notiz $i',
        ),
    ];
    await pumpMemory(tester, items: items);

    expect(addEnabled(tester), isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-memory-footer')),
      400,
    );
    expect(
      find.textContaining('Lösche eine Notiz, um Platz zu schaffen.'),
      findsOneWidget,
    );
  });

  testWidgets('limit reported by the server keeps the sheet and the text', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);
    repository.failWith = limitReached;

    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Noch eine',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();

    expect(find.text('Neue Notiz'), findsOneWidget);
    expect(fieldText(tester), 'Noch eine');
    expect(
      tester.widget<Text>(editorError()).data,
      'Das Gedächtnis ist voll. Lösche zuerst eine Notiz.',
    );
    // Die Liste wird neu geladen, damit die Belegung stimmt.
    expect(repository.calls.last, 'list');
    expect(find.byKey(const ValueKey('coach-memory-error')), findsNothing);
  });

  testWidgets('failed save keeps the sheet open and a retry closes it', (
    tester,
  ) async {
    final repository = await pumpMemory(tester, items: const []);
    repository.failWith = networkError;

    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Keine Nüsse',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();

    expect(find.text('Neue Notiz'), findsOneWidget);
    expect(fieldText(tester), 'Keine Nüsse');
    expect(
      tester.widget<Text>(editorError()).data,
      'Keine Verbindung. Das Gedächtnis lässt sich nur online ändern.',
    );
    // Offline gesperrt: erneutes Sichern nennt den Grund, statt zu senden.
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Notiz'), findsOneWidget);
    expect(repository.calls.where((call) => call.startsWith('create')), [
      'create goal Keine Nüsse',
    ]);
    expect(tester.widget<Text>(editorError()).data, contains('nur online'));

    await tester.tap(find.bySemanticsLabel('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-memory-reload')));
    await tester.pumpAndSettle();
    repository.failWith = serverError;
    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Keine Nüsse',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(editorError()).data,
      'Das hat nicht geklappt. Versuche es erneut.',
    );

    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Notiz'), findsNothing);
    expect(find.text('Keine Nüsse'), findsOneWidget);
  });

  testWidgets('a conflicting edit explains it, reloads and keeps the text', (
    tester,
  ) async {
    final repository = await pumpMemory(tester);
    await tester.tap(find.text('Halbmarathon im Mai'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Marathon im Oktober',
    );
    await tester.pump();
    // Ein anderes Gerät hat die Notiz inzwischen geändert.
    repository.items[0] = memoryItem(
      '11111111-0000-4000-8000-000000000001',
      CoachMemoryCategory.goal,
      'Halbmarathon im Juni',
      version: 2,
    );
    repository.failWith = memoryConflict;

    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();

    expect(find.text('Notiz bearbeiten'), findsOneWidget);
    expect(fieldText(tester), 'Marathon im Oktober');
    expect(
      tester.widget<Text>(editorError()).data,
      contains('inzwischen auf einem anderen Gerät geändert'),
    );
    expect(repository.calls.last, 'list');
    expect(find.text('Halbmarathon im Juni'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();
    expect(repository.baseVersions, [1, 2]);
    expect(find.text('Notiz bearbeiten'), findsNothing);
    expect(find.text('Marathon im Oktober'), findsOneWidget);
  });

  testWidgets('length counts UTF-16 units like the server, also for emoji', (
    tester,
  ) async {
    await pumpMemory(tester, items: const []);
    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('coach-memory-save'));

    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      '💪' * 120,
    );
    await tester.pump();
    // 100 Emoji sind 200 Einheiten; mehr lässt das Feld nicht zu.
    expect(fieldText(tester), '💪' * 100);
    expect(find.text('200 von 200 Zeichen'), findsOneWidget);
    expect(tester.widget<GainerPillButton>(save).onPressed, isNotNull);

    // Kein halbes Emoji: Bei 199 Einheiten passt keins mehr dazu.
    await tester.enterText(find.byKey(const ValueKey('coach-memory-text')), '');
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      '${'a' * 199}💪',
    );
    await tester.pump();
    expect(fieldText(tester), 'a' * 199);
    expect(find.text('199 von 200 Zeichen'), findsOneWidget);
  });

  test('length formatter keeps a full field and passes short edits', () {
    const formatter = CoachMemoryLengthFormatter();
    final full = TextEditingValue(
      text: 'a' * 200,
      selection: const TextSelection.collapsed(offset: 100),
    );
    final longer = TextEditingValue(
      text: '${'a' * 100}💪${'a' * 100}',
      selection: const TextSelection.collapsed(offset: 102),
    );
    expect(formatter.formatEditUpdate(full, longer), full);
    const short = TextEditingValue(text: 'ok');
    expect(formatter.formatEditUpdate(TextEditingValue.empty, short), short);
  });

  testWidgets('a note with an unknown category appears under Sonstiges', (
    tester,
  ) async {
    final list = ApiCoachMemoryList.fromJson({
      'items': [
        {
          'id': '33333333-0000-4000-8000-000000000001',
          'category': 'sleep',
          'text': 'Schläft schlecht',
          'createdAtUtc': '2026-10-24T12:00:00Z',
          'updatedAtUtc': '2026-10-24T12:00:00Z',
          'version': 1,
        },
      ],
      'maxEntries': 50,
    });
    await pumpMemory(tester, items: list.items);

    expect(find.text('Sonstiges'), findsOneWidget);
    expect(find.text('Schläft schlecht'), findsOneWidget);
  });

  testWidgets('remembering a known text with a new category keeps its place', (
    tester,
  ) async {
    final repository = _RecategorizingRepository(sampleMemories());
    await pumpMemory(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('coach-memory-text')),
      'Laktoseintoleranz',
    );
    await tester.tap(find.byKey(const ValueKey('coach-memory-category-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach-memory-save')));
    await tester.pumpAndSettle();

    expect(find.text('Laktoseintoleranz'), findsOneWidget);
    expect(find.text('Unverträglichkeiten'), findsNothing);
    expect(find.text('Sonstiges'), findsOneWidget);
    expect(find.textContaining('4 von 50 Notizen.'), findsOneWidget);
  });

  testWidgets('text size 2 lays out list and sheet without overflow', (
    tester,
  ) async {
    await pumpMemory(tester, textScale: 2, size: const Size(390, 844));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('coach-memory-add')));
    await tester.pumpAndSettle();
    expect(find.text('Unverträglichkeit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('view model ignores changes before the list is loaded', () async {
    final repository = FakeCoachMemoryRepository();
    final model = CoachMemoryViewModel(repository, online: false);
    await model.start();

    expect(model.isOffline, isTrue);
    expect(
      await model.save(category: CoachMemoryCategory.goal, text: 'x'),
      contains('Keine Verbindung'),
    );
    expect(await model.delete('id'), isFalse);
    expect(await model.deleteAll(), isFalse);
    expect(repository.calls, isEmpty);
    model.dispose();
    await model.load();
    expect(repository.calls, isEmpty);
  });

  test('saving the same text again keeps a single entry', () async {
    final existing = sampleMemories().first;
    final repository = _ReturningRepository(existing);
    final model = CoachMemoryViewModel(repository);
    await model.load();

    expect(
      await model.save(category: existing.category, text: existing.text),
      isNull,
    );
    expect(model.items.where((item) => item.id == existing.id), hasLength(1));
    model.dispose();
  });

  test('a recategorized entry is replaced where it stands', () async {
    final repository = _RecategorizingRepository(sampleMemories());
    final model = CoachMemoryViewModel(repository);
    await model.load();
    final order = [for (final item in model.items) item.id];

    expect(
      await model.save(
        category: CoachMemoryCategory.other,
        text: 'Laktoseintoleranz',
      ),
      isNull,
    );

    expect([for (final item in model.items) item.id], order);
    expect(model.items[1].category, CoachMemoryCategory.other);
    expect(model.items[1].version, 2);
    model.dispose();
  });

  test('a busy view model names the reason instead of saving', () async {
    final repository = FakeCoachMemoryRepository(sampleMemories());
    final model = CoachMemoryViewModel(repository);
    await model.load();
    model.isBusy = true;
    expect(
      await model.save(category: CoachMemoryCategory.goal, text: 'x'),
      contains('läuft noch'),
    );
    expect(repository.calls, ['list']);
    model.dispose();
  });
}

/// Liefert beim Anlegen eines vorhandenen Textes den bestehenden Eintrag mit
/// neuer Kategorie und Version zurück, wie der Server.
class _RecategorizingRepository extends FakeCoachMemoryRepository {
  _RecategorizingRepository(super.items);

  @override
  Future<ApiCoachMemory> create(
    CoachMemoryCategory category,
    String text,
  ) async {
    final index = items.indexWhere((item) => item.text == text);
    if (index < 0) return super.create(category, text);
    calls.add('create ${category.wireName} $text');
    final existing = items[index];
    return items[index] = memoryItem(
      existing.id,
      category,
      existing.text,
      version: existing.version + 1,
    );
  }
}

/// Liefert beim Anlegen den schon vorhandenen Eintrag zurück, wie der Server
/// bei einem Duplikat.
class _ReturningRepository extends FakeCoachMemoryRepository {
  _ReturningRepository(this.existing) : super([existing]);

  final ApiCoachMemory existing;

  @override
  Future<ApiCoachMemory> create(
    CoachMemoryCategory category,
    String text,
  ) async => existing;
}
