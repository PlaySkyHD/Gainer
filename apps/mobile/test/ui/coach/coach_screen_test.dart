import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/coach/coach_screen.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';

void main() {
  testWidgets('empty coach shows the question field and no answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi((_) async => _answer());
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coach'), findsWidgets);
    expect(
      find.text('Frage zu deinem Training oder deiner Entwicklung'),
      findsOneWidget,
    );
    expect(find.text('Frage senden'), findsOneWidget);
    expect(find.text('Datengrundlage: Revision 9'), findsNothing);
    expect(api.questions, isEmpty);
  });

  testWidgets('blank question is rejected locally without a request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi((_) async => _answer());
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), '   ');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(
      find.text('Gib eine Frage mit höchstens 1000 Zeichen ein.'),
      findsOneWidget,
    );
    expect(api.questions, isEmpty);
  });

  testWidgets('trimmed question renders the full structured answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi((_) async => _answer());
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(
      find.byType(CupertinoTextField),
      '  Wie regelmäßig war mein Training zuletzt?  ',
    );
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(api.questions, ['Wie regelmäßig war mein Training zuletzt?']);
    expect(find.text('Dein Training ist konstant.'), findsOneWidget);
    expect(find.text('Drei Einheiten pro Woche.'), findsOneWidget);
    expect(find.text('Zwei Wochen ohne Schlafdaten.'), findsOneWidget);
    expect(find.text('Mögliche nächste Schritte'), findsOneWidget);
    expect(find.text('Plane einen Deload-Tag.'), findsOneWidget);
    expect(
      find.text('Für eine vollständigere Auswertung fehlen noch Daten:'),
      findsOneWidget,
    );
    expect(find.text('Schlafdaten fehlen.'), findsOneWidget);
    expect(find.text('Datengrundlage: Revision 9'), findsOneWidget);
    expect(find.text('•  '), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('answer without suggestions or gaps omits those sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi(
      (_) async => const ApiCoachResponse(
        summary: 'Alles im Plan.',
        observations: ['Gleichmäßige Trainingstage.'],
        dataGaps: [],
        suggestions: [],
        asOfRevision: 3,
      ),
    );
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), 'Wie läuft es?');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(find.text('Alles im Plan.'), findsOneWidget);
    expect(find.text('Gleichmäßige Trainingstage.'), findsOneWidget);
    expect(find.text('Mögliche nächste Schritte'), findsNothing);
    expect(
      find.text('Für eine vollständigere Auswertung fehlen noch Daten:'),
      findsNothing,
    );
    expect(find.text('Datengrundlage: Revision 3'), findsOneWidget);
  });

  testWidgets('pending question disables sending until the answer arrives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<ApiCoachResponse>();
    final api = _CoachApi((_) => gate.future);
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), 'Wie geht es?');
    await tester.tap(find.text('Frage senden'));
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('Frage senden'), findsNothing);
    final button = tester.widget<CupertinoButton>(find.byType(CupertinoButton));
    expect(button.onPressed, isNull);

    gate.complete(_answer());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Frage senden'), findsOneWidget);
    expect(find.text('Dein Training ist konstant.'), findsOneWidget);
  });

  testWidgets('failed request shows a safe message and can be retried', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi((question) async {
      if (question == 'Erster Versuch') {
        throw const ApiException(
          statusCode: 503,
          code: 'unavailable',
          message: 'unavailable',
        );
      }
      return _answer();
    });
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), 'Erster Versuch');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Der Coach ist gerade nicht verfügbar. Deine Frage wurde nicht gespeichert.',
      ),
      findsOneWidget,
    );
    expect(find.text('Dein Training ist konstant.'), findsNothing);

    await tester.enterText(find.byType(CupertinoTextField), 'Zweiter Versuch');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(api.questions, ['Erster Versuch', 'Zweiter Versuch']);
    expect(find.textContaining('nicht verfügbar'), findsNothing);
    expect(find.text('Dein Training ist konstant.'), findsOneWidget);
  });

  testWidgets('Tageslimit zeigt einen eigenen Hinweis', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CoachApi((_) async {
      throw const ApiException(
        statusCode: 429,
        code: 'daily_budget_exhausted',
        message: 'budget',
      );
    });
    final model = CoachViewModel(CoachRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: CoachScreen(viewModel: model),
      ),
    );
    await tester.enterText(find.byType(CupertinoTextField), 'Wie läuft es?');
    await tester.tap(find.text('Frage senden'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Das Tageslimit für den Coach ist erreicht. Morgen geht es wieder.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('nicht verfügbar'), findsNothing);
  });
}

ApiCoachResponse _answer() => const ApiCoachResponse(
  summary: 'Dein Training ist konstant.',
  observations: ['Drei Einheiten pro Woche.', 'Zwei Wochen ohne Schlafdaten.'],
  dataGaps: ['Schlafdaten fehlen.'],
  suggestions: ['Plane einen Deload-Tag.'],
  asOfRevision: 9,
);

class _CoachApi extends ApiClient {
  _CoachApi(this.onAsk)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Future<ApiCoachResponse> Function(String question) onAsk;
  final questions = <String>[];

  @override
  Future<ApiCoachResponse> askCoach(String question) {
    questions.add(question);
    return onAsk(question);
  }
}
