import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/coach/coach_screen.dart';
import 'package:gainer_mobile/ui/features/coach/coach_view_model.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('coach screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _CoachApi(
        (_) async => const ApiCoachResponse(
          summary: 'Dein Training ist konstant.',
          observations: [
            'Drei Einheiten pro Woche.',
            'Zwei Wochen ohne Schlafdaten.',
          ],
          dataGaps: ['Schlafdaten fehlen.'],
          suggestions: ['Plane einen Deload-Tag.'],
          asOfRevision: 9,
        ),
      );
      final model = CoachViewModel(CoachRepository(api));
      addTearDown(model.dispose);
      addTearDown(api.close);

      await tester.pumpWidget(
        CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: GainerTheme.forBrightness(brightness),
          home: CoachScreen(viewModel: model),
        ),
      );
      await tester.enterText(
        find.byType(CupertinoTextField),
        'Wie regelmäßig war mein Training zuletzt?',
      );
      await tester.tap(find.text('Frage senden'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(CoachScreen),
        matchesGoldenFile('goldens/coach_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _CoachApi extends ApiClient {
  _CoachApi(this.onAsk)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Future<ApiCoachResponse> Function(String question) onAsk;

  @override
  Future<ApiCoachResponse> askCoach(String question) => onAsk(question);
}
