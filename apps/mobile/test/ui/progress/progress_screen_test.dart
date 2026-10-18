import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/progress/progress_screen.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('progress screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      _useGoldenPhone(tester);
      final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
      final model = ProgressViewModel(InsightsRepository(api));
      addTearDown(model.dispose);
      addTearDown(api.close);

      await _pumpGolden(tester, brightness, ProgressScreen(viewModel: model));

      await expectLater(
        find.byType(ProgressScreen),
        matchesGoldenFile('goldens/progress_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }

  testWidgets('dashboard shows weight, training, nutrition and trend values', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(api.calls, 1);
    expect(find.text('Heute'), findsNWidgets(2));
    // Kein Untertitel unter dem großen Titel (design.md D1.1).
    expect(find.text('Dein Fortschritt aus deinen Einträgen'), findsNothing);
    expect(
      find.text('Die Werte beruhen auf deinen gespeicherten Einträgen.'),
      findsOneWidget,
    );
    expect(
      find.text('Gespeicherte Fortschrittsdaten · möglicherweise veraltet'),
      findsNothing,
    );

    expect(find.text('Gewicht'), findsOneWidget);
    expect(find.text('3 von 30 Tagen mit Eintrag'), findsOneWidget);
    expect(find.text('Letzter Eintrag · 14.10.2026'), findsOneWidget);
    expect(find.text('81.5 kg'), findsOneWidget);
    expect(find.text('Ø 7 Tage · 81.2 kg'), findsOneWidget);
    expect(find.text('Ø 30 Tage · 81.8 kg'), findsOneWidget);
    expect(find.text('-0.40 kg pro Woche'), findsOneWidget);
    expect(
      _chartLabel('Gewichtsverlauf. 2026-10-12: 82.0 kg, 2026-10-14: 81.5 kg'),
      findsOneWidget,
    );
    expect(
      find.text('Nach dem ersten Check-in erscheint hier dein Verlauf.'),
      findsNothing,
    );

    expect(find.text('Training'), findsOneWidget);
    expect(find.text('4 Workouts in den letzten 7 Tagen'), findsOneWidget);
    expect(find.text('Workouts gesamt'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Trainingsvolumen'), findsOneWidget);
    expect(find.text('4200 kg × Wdh.'), findsOneWidget);

    expect(find.text('Ernährung'), findsOneWidget);
    expect(
      find.text('Abdeckung 53% · 9 Tage im Ernährungstagebuch'),
      findsOneWidget,
    );
    expect(find.text('2350 kcal pro erfasstem Tag'), findsOneWidget);
    expect(find.text('145 g Protein pro erfasstem Tag'), findsOneWidget);

    expect(find.text('Aktives Ziel'), findsOneWidget);
    expect(find.text('78.0 kg  →  82.0 kg'), findsOneWidget);
    expect(find.text('Aktualisieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty dashboard explains missing check-ins and nutrition', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _emptyInsights());
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(find.text('0 von 30 Tagen mit Eintrag'), findsOneWidget);
    expect(find.textContaining('Letzter Eintrag'), findsNothing);
    expect(
      find.text('Noch keine Gewichtsdaten der letzten 7 Tage'),
      findsOneWidget,
    );
    expect(find.text('Ø 30 Tage · Noch keine Gewichtsdaten'), findsOneWidget);
    expect(
      find.text('Nach dem ersten Check-in erscheint hier dein Verlauf.'),
      findsOneWidget,
    );
    expect(
      find.text('Abdeckung 100% · 0 Tage im Ernährungstagebuch'),
      findsOneWidget,
    );
    expect(find.text('Noch keine Kalorienwerte erfasst.'), findsOneWidget);
    expect(find.text('Noch keine Proteinwerte erfasst.'), findsOneWidget);
    expect(find.text('Aktives Ziel'), findsNothing);
    expect(find.textContaining('kg pro Woche'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal kinds map to German labels', (tester) async {
    _useTallView(tester);
    const cases = {
      'bulk': 'Muskelaufbau',
      'MAINTAIN': 'Gewicht halten',
      'cut': 'Gewicht reduzieren',
      'recomposition': 'Körperziel',
    };
    for (final entry in cases.entries) {
      final api = _DashboardApi(
        (_) async => _insights(
          activeGoal: ApiActiveGoalInsight(
            kind: entry.key,
            startWeightKg: 78,
            targetWeightKg: 82,
            startDate: '2026-09-01',
          ),
        ),
      );
      final model = ProgressViewModel(InsightsRepository(api));
      addTearDown(model.dispose);
      addTearDown(api.close);
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(tester, model, key: ValueKey(entry.key));

      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      expect(find.text('78.0 kg  →  82.0 kg'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('spinner shows until the first dashboard response arrives', (
    tester,
  ) async {
    _useTallView(tester);
    final gate = Completer<ApiDashboardInsights>();
    final api = _DashboardApi((_) => gate.future);
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: ProgressScreen(viewModel: model),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('Aktualisieren'), findsNothing);
    expect(find.text('Gewicht'), findsNothing);

    gate.complete(_insights());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Gewicht'), findsOneWidget);
    expect(find.text('Aktualisieren'), findsOneWidget);
  });

  testWidgets('refresh is disabled while reloading and fetches again', (
    tester,
  ) async {
    _useTallView(tester);
    final gate = Completer<ApiDashboardInsights>();
    final api = _DashboardApi((call) async {
      if (call == 1) return _insights();
      return gate.future;
    });
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);
    await tester.tap(find.text('Aktualisieren'));
    await tester.pump();

    expect(api.calls, 2);
    final button = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, 'Aktualisieren'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Gewicht'), findsOneWidget);

    gate.complete(_insights(trendKgPerWeek: 0.5));
    await tester.pumpAndSettle();

    final enabled = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, 'Aktualisieren'),
    );
    expect(enabled.onPressed, isNotNull);
    expect(find.text('+0.50 kg pro Woche'), findsOneWidget);
  });

  testWidgets('failed first load shows a safe error and retry recovers', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((call) async {
      if (call == 1) throw StateError('offline');
      return _insights();
    });
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(
      find.text(
        'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.',
      ),
      findsOneWidget,
    );
    expect(find.text('Gewicht'), findsNothing);
    expect(find.text('Aktualisieren'), findsNothing);

    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(api.calls, 2);
    expect(
      find.text(
        'Fortschritt ist gerade nicht verfügbar. Bitte verbinde dich erneut.',
      ),
      findsNothing,
    );
    expect(find.text('Gewicht'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh keeps cached values visible and marked stale', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => throw StateError('offline'));
    final model = ProgressViewModel(
      _CachedInsights(
        api,
        CachedDashboardInsights(
          value: _insights(trendKgPerWeek: -0.25),
          cachedAtUtc: DateTime.utc(2026, 10, 14, 8),
        ),
      ),
    );
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(
      find.text('Gespeicherte Fortschrittsdaten · möglicherweise veraltet'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Fortschritt konnte nicht aktualisiert werden; gespeicherte Werte bleiben sichtbar.',
      ),
      findsOneWidget,
    );
    expect(find.text('81.5 kg'), findsOneWidget);
    expect(find.text('-0.25 kg pro Woche'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Aktualisieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard names missing bodyweight in text, not only color', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights(bodyweightMissing: true));
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(
      find.text('Für korrekte Werte fehlt ein Check-in mit Körpergewicht.'),
      findsOneWidget,
    );
    expect(find.text('Trainingsvolumen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weight chart paints a single point and a flat series', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi(
      (_) async => _insights(
        weightSeries: const [
          ApiWeightPoint(date: '2026-10-14', weightKg: 81.5),
        ],
      ),
    );
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);
    expect(_chartLabel('Gewichtsverlauf. 2026-10-14: 81.5 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    final flat = ProgressViewModel(
      InsightsRepository(
        _DashboardApi(
          (_) async => _insights(
            weightSeries: const [
              ApiWeightPoint(date: '2026-10-10', weightKg: 80),
              ApiWeightPoint(date: '2026-10-11', weightKg: 80),
              ApiWeightPoint(date: '2026-10-12', weightKg: 80),
            ],
          ),
        ),
      ),
    );
    addTearDown(flat.dispose);
    await _pumpScreen(tester, flat, key: const ValueKey('flat'));

    expect(
      _chartLabel(
        'Gewichtsverlauf. 2026-10-10: 80.0 kg, 2026-10-11: 80.0 kg, 2026-10-12: 80.0 kg',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _chartLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void _useGoldenPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpGolden(
  WidgetTester tester,
  Brightness brightness,
  Widget screen,
) async {
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GainerTheme.forBrightness(brightness),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProgressViewModel model, {
  Key? key,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      theme: GainerTheme.light,
      home: ProgressScreen(key: key, viewModel: model),
    ),
  );
  await tester.pumpAndSettle();
}

ApiDashboardInsights _insights({
  List<ApiWeightPoint> weightSeries = const [
    ApiWeightPoint(date: '2026-10-12', weightKg: 82),
    ApiWeightPoint(date: '2026-10-14', weightKg: 81.5),
  ],
  double? trendKgPerWeek = 0.25,
  ApiActiveGoalInsight? activeGoal,
  bool bodyweightMissing = false,
}) => ApiDashboardInsights(
  asOfRevision: 7,
  from: '2026-09-16',
  through: '2026-10-16',
  weightSeries: weightSeries,
  latestWeight: weightSeries.isEmpty ? null : weightSeries.last,
  sevenDayWeight: const ApiWeightInsights(
    unit: 'kg',
    expectedDays: 7,
    observedDays: 2,
    coverage: .29,
    averageKg: 81.2,
  ),
  weight: ApiWeightInsights(
    unit: 'kg',
    expectedDays: 30,
    observedDays: 3,
    coverage: .1,
    averageKg: 81.8,
    trendKgPerWeek: trendKgPerWeek,
  ),
  nutrition: const ApiNutritionInsights(
    expectedDays: 30,
    observedDays: 9,
    coverage: .53,
    mealDiaryDays: 9,
    legacyCheckInDays: 0,
    caloriesKcal: ApiMetricAverage(value: 2350.4, observedDays: 9),
    proteinGrams: ApiMetricAverage(value: 145.2, observedDays: 9),
    carbohydrateGrams: ApiMetricAverage(observedDays: 9),
    fatGrams: ApiMetricAverage(observedDays: 9),
  ),
  training: ApiTrainingInsights(
    workoutCount: 12,
    volumeKgRepetitions: 4200.4,
    volumeAlgorithmVersion: 'training-volume-v2',
    estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
    volumeUnit: 'kg-repetitions',
    bestSet: null,
    bodyweightMissing: bodyweightMissing,
  ),
  workoutsLast7Days: 4,
  activeGoal:
      activeGoal ??
      const ApiActiveGoalInsight(
        kind: 'cut',
        startWeightKg: 78,
        targetWeightKg: 82,
        startDate: '2026-09-01',
      ),
);

ApiDashboardInsights _emptyInsights() => const ApiDashboardInsights(
  asOfRevision: 0,
  from: '2026-09-16',
  through: '2026-10-16',
  weightSeries: [],
  sevenDayWeight: ApiWeightInsights(
    unit: 'kg',
    expectedDays: 7,
    observedDays: 0,
    coverage: 0,
  ),
  weight: ApiWeightInsights(
    unit: 'kg',
    expectedDays: 30,
    observedDays: 0,
    coverage: 0,
  ),
  nutrition: ApiNutritionInsights(
    expectedDays: 30,
    observedDays: 0,
    coverage: 1.4,
    mealDiaryDays: 0,
    legacyCheckInDays: 0,
    caloriesKcal: ApiMetricAverage(observedDays: 0),
    proteinGrams: ApiMetricAverage(observedDays: 0),
    carbohydrateGrams: ApiMetricAverage(observedDays: 0),
    fatGrams: ApiMetricAverage(observedDays: 0),
  ),
  training: ApiTrainingInsights(
    workoutCount: 0,
    volumeKgRepetitions: 0,
    volumeAlgorithmVersion: 'training-volume-v2',
    estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
    volumeUnit: 'kg-repetitions',
    bestSet: null,
    bodyweightMissing: false,
  ),
  workoutsLast7Days: 0,
);

class _DashboardApi extends ApiClient {
  _DashboardApi(this.onLoad)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          trustedFrontendOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  final Future<ApiDashboardInsights> Function(int call) onLoad;
  int calls = 0;

  @override
  Future<ApiDashboardInsights> getDashboardInsights({
    int days = 30,
    DateTime? through,
  }) {
    calls++;
    return onLoad(calls);
  }
}

class _CachedInsights extends InsightsRepository {
  _CachedInsights(super.api, this.cached);

  final CachedDashboardInsights cached;

  @override
  Future<CachedDashboardInsights?> readCachedDashboard({int days = 30}) async =>
      cached;
}
