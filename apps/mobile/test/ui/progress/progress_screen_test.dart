import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/ui/core/shell/mobile_tab_scaffold.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_screen.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';

/// Fester Sonntag, damit das Datum unter dem Titel stabil ist.
DateTime _today() => DateTime(2026, 10, 18);

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('progress screen matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      _useGoldenPhone(tester);
      final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
      final model = ProgressViewModel(
        InsightsRepository(api),
        nutrition: _FakeNutrition(kcal: 1280, protein: 42),
      );
      addTearDown(model.dispose);
      addTearDown(api.close);

      await _pumpGolden(
        tester,
        brightness,
        ProgressScreen(viewModel: model, today: _today),
      );

      await expectLater(
        find.byType(ProgressScreen),
        matchesGoldenFile('goldens/progress_screen_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }

  testWidgets('dashboard shows nutrition, weight and training cards', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
    final model = ProgressViewModel(
      InsightsRepository(api),
      nutrition: _FakeNutrition(kcal: 1280, protein: 42),
    );
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(api.calls, 1);
    expect(find.text('Heute'), findsNWidgets(2));
    expect(find.text('Sonntag, 18. Oktober'), findsOneWidget);
    // Kein Untertitel, keine Erklärsätze und keine Toolbar-Pille mehr.
    expect(find.text('Dein Fortschritt aus deinen Einträgen'), findsNothing);
    expect(find.text('Aktualisieren'), findsNothing);
    expect(
      find.text('Die Werte beruhen auf deinen gespeicherten Einträgen.'),
      findsNothing,
    );
    expect(find.text('Übungsfortschritt'), findsNothing);
    expect(
      find.text('Gespeicherte Fortschrittsdaten · möglicherweise veraltet'),
      findsNothing,
    );

    // Werte sind deutsch formatiert (Komma, Tausenderpunkt).
    expect(find.text('Ernährung'), findsOneWidget);
    expect(_rich('1.280 kcal heute'), findsOneWidget);
    expect(find.text('Protein 42 g'), findsOneWidget);

    expect(find.text('Gewicht'), findsOneWidget);
    expect(_rich('81,5 kg'), findsOneWidget);
    expect(find.text('vor 4 Tagen'), findsOneWidget);
    expect(find.text('−0,4 kg/Woche'), findsOneWidget);
    expect(find.text('Ziel 82,0 kg'), findsOneWidget);
    expect(
      _chartLabel('Gewichtsverlauf. 2026-10-12: 82.0 kg, 2026-10-14: 81.5 kg'),
      findsOneWidget,
    );

    expect(find.text('Training'), findsOneWidget);
    expect(_rich('4 Trainings in 7 Tagen'), findsOneWidget);
    expect(find.text('Volumen 4.200 kg · 30 Tage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty diary day shows 0 kcal heute', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final model = ProgressViewModel(
      InsightsRepository(api),
      nutrition: _FakeNutrition(kcal: 0),
    );
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(_rich('0 kcal heute'), findsOneWidget);
    expect(find.textContaining('Noch nichts erfasst'), findsNothing);
    expect(find.textContaining('Protein'), findsNothing);
  });

  testWidgets('returning to the tab refreshes today from local data', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final nutrition = _FakeNutrition(kcal: 100);
    final model = ProgressViewModel(
      InsightsRepository(api),
      nutrition: nutrition,
    );
    final tabs = ValueNotifier<int>(0);
    addTearDown(model.dispose);
    addTearDown(api.close);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: ProgressScreen(
          viewModel: model,
          today: _today,
          visibility: tabs,
          isVisible: () => tabs.value == 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_rich('100 kcal heute'), findsOneWidget);

    tabs.value = 1;
    nutrition.kcal = 450;
    await tester.pumpAndSettle();
    expect(_rich('100 kcal heute'), findsOneWidget);

    tabs.value = 0;
    await tester.pumpAndSettle();
    expect(_rich('450 kcal heute'), findsOneWidget);
  });

  testWidgets('cards do not overflow at text scale 2', (tester) async {
    _useGoldenPhone(tester);
    final api = _DashboardApi(
      (_) async => _insights(
        trendKgPerWeek: null,
        weightSeries: const [
          ApiWeightPoint(date: '2026-10-09', weightKg: 81.5),
        ],
      ),
    );
    final model = ProgressViewModel(
      InsightsRepository(api),
      nutrition: _FakeNutrition(kcal: 12800, protein: 420),
    );
    addTearDown(model.dispose);
    addTearDown(api.close);
    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ProgressScreen(viewModel: model, today: _today),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('vor 9 Tagen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('weight age label', () {
    const cases = <(String, String, bool, bool)>[
      ('2026-10-18', 'Heute', false, false),
      ('2026-10-17', 'Gestern', false, false),
      ('2026-10-16', 'vor 2 Tagen', true, false),
      ('2026-10-12', 'vor 6 Tagen', true, false),
      ('2026-10-11', 'vor 7 Tagen', false, true),
      ('2026-09-18', 'vor 30 Tagen', false, true),
    ];
    for (final (date, label, warning, destructive) in cases) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets('$date reads "$label" in ${brightness.name}', (
          tester,
        ) async {
          _useTallView(tester);
          final api = _DashboardApi(
            (_) async => _insights(
              weightSeries: [ApiWeightPoint(date: date, weightKg: 81.5)],
            ),
          );
          final model = ProgressViewModel(InsightsRepository(api));
          addTearDown(model.dispose);
          addTearDown(api.close);
          await tester.pumpWidget(
            CupertinoApp(
              theme: brightness == Brightness.dark
                  ? GainerTheme.dark
                  : GainerTheme.light,
              home: ProgressScreen(viewModel: model, today: _today),
            ),
          );
          await tester.pumpAndSettle();

          final finder = find.text(label).last;
          expect(find.text(label), findsWidgets);
          final colors = brightness == Brightness.dark
              ? GainerColors.dark
              : GainerColors.light;
          final expected = warning
              ? colors.warning
              : destructive
              ? colors.destructive
              : colors.secondaryText;
          expect(tester.widget<Text>(finder).style?.color, expected);
          expect(_chartLabel('Letztes Gewicht: $label'), findsOneWidget);
        });
      }
    }
  });

  testWidgets('a single training reads in singular and trend gets a plus', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi(
      (_) async => _insights(trendKgPerWeek: 0.5, workoutsLast7Days: 1),
    );
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(_rich('1 Training in 7 Tagen'), findsOneWidget);
    expect(find.text('+0,5 kg/Woche'), findsOneWidget);
  });

  testWidgets('empty dashboard shows short empty states', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _emptyInsights());
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(find.text('Noch nichts erfasst'), findsOneWidget);
    expect(find.text('Noch kein Gewicht'), findsOneWidget);
    expect(find.text('Check-in eintragen'), findsOneWidget);
    expect(find.text('Noch kein Training diese Woche'), findsOneWidget);
    expect(find.textContaining('Protein'), findsNothing);
    expect(find.textContaining('Ziel'), findsNothing);
    expect(find.textContaining('kg/Woche'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each card opens its tab through the shell', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final progress = ProgressViewModel(InsightsRepository(api));
    final shell = MobileShellViewModel();
    addTearDown(progress.dispose);
    addTearDown(shell.dispose);
    addTearDown(api.close);

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.light,
        home: MobileTabScaffold(
          model: shell,
          tabBuilder: (context, area) => area == MobileArea.progress
              ? ProgressScreen(
                  viewModel: progress,
                  today: _today,
                  onOpenArea: (target) => shell.selectTab(target.index),
                )
              : CupertinoPageScaffold(child: Text('Inhalt ${area.label}')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const cards = {
      'Ernährung': MobileArea.nutrition,
      'Gewicht': MobileArea.body,
      'Training': MobileArea.training,
    };
    for (final entry in cards.entries) {
      shell.selectTab(MobileArea.progress.index);
      await tester.pumpAndSettle();
      expect(shell.selectedArea, MobileArea.progress);

      await tester.tap(find.widgetWithText(CupertinoButton, entry.key).first);
      await tester.pumpAndSettle();

      expect(shell.selectedArea, entry.value, reason: entry.key);
      expect(find.text('Inhalt ${entry.value.label}'), findsOneWidget);
    }
  });

  testWidgets('cards do nothing without a tab callback', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);
    await tester.tap(find.widgetWithText(CupertinoButton, 'Ernährung'));
    await tester.pumpAndSettle();

    expect(find.text('Ernährung'), findsOneWidget);
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
    expect(find.text('Gewicht'), findsNothing);

    gate.complete(_insights());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Gewicht'), findsOneWidget);
  });

  testWidgets('pulling down reloads the dashboard', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi(
      (call) async => _insights(trendKgPerWeek: call == 1 ? -0.4 : 0.5),
    );
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);
    expect(api.calls, 1);
    expect(find.text('−0,4 kg/Woche'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(api.calls, 2);
    expect(find.text('+0,5 kg/Woche'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
          value: _insights(trendKgPerWeek: -0.5),
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
    expect(_rich('81,5 kg'), findsOneWidget);
    expect(find.text('vor 4 Tagen'), findsOneWidget);
    expect(find.text('−0,5 kg/Woche'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single weight point shows the value without a chart', (
    tester,
  ) async {
    _useTallView(tester);
    final api = _DashboardApi(
      (_) async => _insights(
        trendKgPerWeek: null,
        weightSeries: const [
          ApiWeightPoint(date: '2026-10-14', weightKg: 81.5),
        ],
      ),
    );
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(_rich('81,5 kg'), findsOneWidget);
    expect(find.text('vor 4 Tagen'), findsOneWidget);
    expect(_chartLabel('Gewichtsverlauf. 2026-10-14: 81.5 kg'), findsNothing);
  });

  testWidgets('weight chart paints a flat series', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi(
      (_) async => _insights(
        trendKgPerWeek: null,
        weightSeries: const [
          ApiWeightPoint(date: '2026-10-10', weightKg: 80),
          ApiWeightPoint(date: '2026-10-11', weightKg: 80),
          ApiWeightPoint(date: '2026-10-12', weightKg: 80),
        ],
      ),
    );
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(
      _chartLabel(
        'Gewichtsverlauf. 2026-10-10: 80.0 kg, 2026-10-11: 80.0 kg, 2026-10-12: 80.0 kg',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _rich(String text) => find.text(text, findRichText: true);

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
      home: ProgressScreen(key: key, viewModel: model, today: _today),
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
  int workoutsLast7Days = 4,
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
  workoutsLast7Days: workoutsLast7Days,
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

class _FakeNutrition implements NutritionRepository {
  _FakeNutrition({required this.kcal, this.protein});

  double kcal;
  double? protein;

  @override
  Future<NutritionSnapshot> read(String localDate) async => NutritionSnapshot(
    day: NutritionDay(
      localDate: localDate,
      entries: kcal == 0
          ? const []
          : [
              NutritionEntry(
                entryId: '00000000-0000-4000-8000-000000000001',
                meal: NutritionMeal.breakfast,
                position: 0,
                productName: 'Test',
                brand: null,
                amountGrams: 100,
                per100Grams: NutritionTotals(
                  kilocalories: kcal,
                  proteinGrams: protein,
                ),
                source: null,
              ),
            ],
    ),
    meals: const [],
    targetSchedule: null,
    recentFoods: const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
