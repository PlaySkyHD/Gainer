import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/core/theme.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/today_overview.dart';

/// Fester Sonntag als heutiger Tag.
DateTime _today() => DateTime(2026, 10, 18);

void main() {
  group('weightChartPositions', () {
    const size = Size(100, 80);

    test('places x by date, not by index, and y at the data value', () {
      final positions = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
        ApiWeightPoint(date: '2026-10-11', weightKg: 80),
        ApiWeightPoint(date: '2026-10-20', weightKg: 90),
      ], size);

      expect(positions, hasLength(3));
      // 5 px Rand für den Marker, 90 px nutzbar.
      expect(positions[0].dx, 5);
      expect(positions[1].dx, closeTo(14, 1e-9));
      expect(positions[2].dx, 95);
      // Mittlerer Punkt liegt auf der Höhe des ersten, nicht dazwischen.
      expect(positions[1].dy, positions[0].dy);
      expect(positions[2].dy, lessThan(positions[1].dy));
    });

    test('falls back to index spacing for identical or invalid dates', () {
      final same = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
        ApiWeightPoint(date: '2026-10-10', weightKg: 81),
        ApiWeightPoint(date: '2026-10-10', weightKg: 82),
      ], size);
      expect(same.map((p) => p.dx), [5, 50, 95]);

      final invalid = weightChartPositions(const [
        ApiWeightPoint(date: 'kaputt', weightKg: 80),
        ApiWeightPoint(date: '2026-10-10', weightKg: 81),
      ], size);
      expect(invalid.map((p) => p.dx), [5, 95]);
    });

    test('keeps x inside the chart for an unsorted series', () {
      final positions = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-20', weightKg: 90),
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
        ApiWeightPoint(date: '2026-10-11', weightKg: 80),
      ], size);
      expect(positions.map((p) => p.dx), [95, 5, closeTo(14, 1e-9)]);
      expect(positions.every((p) => p.dx >= 0 && p.dx <= 100), isTrue);
    });

    test('uses only the date part, ignoring a time offset', () {
      final positions = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-20T23:30:00-02:00', weightKg: 80),
        ApiWeightPoint(date: '2026-10-21', weightKg: 80),
      ], size);
      expect(positions.map((p) => p.dx), [5, 95]);
      expect(
        weightPointLabel(
          const ApiWeightPoint(date: '2026-10-20T23:30:00-02:00', weightKg: 80),
        ),
        '20.10.2026: 80,0 kg',
      );
    });

    test('centres a flat series on the middle grid line', () {
      final positions = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
        ApiWeightPoint(date: '2026-10-11', weightKg: 80),
      ], size);
      expect(positions.every((p) => p.dy == 40), isTrue);
    });

    test('handles width 0 and a single point', () {
      final zero = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
        ApiWeightPoint(date: '2026-10-12', weightKg: 90),
      ], Size.zero);
      expect(zero, hasLength(2));
      expect(zero.every((p) => p.dx == 0 && p.dx.isFinite), isTrue);

      final single = weightChartPositions(const [
        ApiWeightPoint(date: '2026-10-10', weightKg: 80),
      ], size);
      expect(single.single.dx, 50);
      expect(weightChartPositions(const [], size), isEmpty);
    });

    test('formats the spoken label in German', () {
      expect(
        weightPointLabel(
          const ApiWeightPoint(date: '2026-10-20', weightKg: 80.5),
        ),
        '20.10.2026: 80,5 kg',
      );
    });
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('overview matches golden in ${brightness.name} mode', (
      tester,
    ) async {
      _useGoldenPhone(tester);
      final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
      final model = ProgressViewModel(InsightsRepository(api));
      addTearDown(model.dispose);
      addTearDown(api.close);

      await _pumpScreen(tester, model, brightness: brightness);

      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/today_overview_${brightness.name}.png'),
      );
      expect(tester.takeException(), isNull);
    }, tags: ['golden']);
  }

  testWidgets('overview shows weight and training cards', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights(trendKgPerWeek: -0.4));
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);

    expect(api.calls, 1);
    expect(
      find.text('Gespeicherte Fortschrittsdaten · möglicherweise veraltet'),
      findsNothing,
    );
    // Die Ernährung von heute zeigt der Kalender selbst.
    expect(find.textContaining('kcal heute', findRichText: true), findsNothing);

    expect(find.text('Gewicht'), findsOneWidget);
    expect(_rich('81,5 kg'), findsOneWidget);
    expect(find.text('vor 4 Tagen'), findsOneWidget);
    expect(find.text('−0,4 kg/Woche'), findsOneWidget);
    expect(find.text('Ziel 82,0 kg'), findsOneWidget);
    expect(
      _chartLabel('Gewichtsverlauf. 12.10.2026: 82,0 kg, 14.10.2026: 81,5 kg'),
      findsOneWidget,
    );

    expect(find.text('Trainingsübersicht'), findsOneWidget);
    expect(_rich('4 Trainings in 7 Tagen'), findsOneWidget);
    expect(find.text('Volumen 4.200 kg · 30 Tage'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model, textScale: 2);

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
          await _pumpScreen(tester, model, brightness: brightness);

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

    expect(find.text('Noch kein Gewicht'), findsOneWidget);
    expect(find.text('Check-in eintragen'), findsOneWidget);
    expect(find.text('Noch kein Training diese Woche'), findsOneWidget);
    expect(find.textContaining('Ziel'), findsNothing);
    expect(find.textContaining('kg/Woche'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards call their tap callbacks', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);
    final taps = <String>[];

    await _pumpScreen(
      tester,
      model,
      onWeight: () => taps.add('weight'),
      onTraining: () => taps.add('training'),
    );
    await tester.tap(find.widgetWithText(CupertinoButton, 'Gewicht'));
    await tester.tap(
      find.widgetWithText(CupertinoButton, 'Trainingsübersicht'),
    );
    await tester.pumpAndSettle();

    expect(taps, ['weight', 'training']);
  });

  testWidgets('cards do nothing without a tap callback', (tester) async {
    _useTallView(tester);
    final api = _DashboardApi((_) async => _insights());
    final model = ProgressViewModel(InsightsRepository(api));
    addTearDown(model.dispose);
    addTearDown(api.close);

    await _pumpScreen(tester, model);
    await tester.tap(find.widgetWithText(CupertinoButton, 'Gewicht'));
    await tester.pumpAndSettle();

    expect(find.text('Gewicht'), findsOneWidget);
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
        home: _Overview(model: model),
      ),
    );
    unawaited(model.load());
    await tester.pump();
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('Gewicht'), findsNothing);

    gate.complete(_insights());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('Gewicht'), findsOneWidget);
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

  testWidgets('cached values are not marked stale while refreshing', (
    tester,
  ) async {
    _useTallView(tester);
    final response = Completer<ApiDashboardInsights>();
    final api = _DashboardApi((_) => response.future);
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
    const hint = 'Gespeicherte Fortschrittsdaten · möglicherweise veraltet';

    await tester.pumpWidget(
      CupertinoApp(
        theme: GainerTheme.forBrightness(Brightness.light),
        home: _Overview(model: model),
      ),
    );
    unawaited(model.load());
    await tester.pump();
    // Die gespeicherten Werte stehen schon da, ohne Hinweis.
    expect(_rich('81,5 kg'), findsOneWidget);
    expect(find.text(hint), findsNothing);

    response.complete(_insights(trendKgPerWeek: -0.4));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expect(find.text('−0,4 kg/Woche'), findsOneWidget);
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

  testWidgets('overview names missing bodyweight in text, not only color', (
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
    expect(_chartLabel('Gewichtsverlauf. 14.10.2026: 81,5 kg'), findsNothing);
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
        'Gewichtsverlauf. 10.10.2026: 80,0 kg, 11.10.2026: 80,0 kg, 12.10.2026: 80,0 kg',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('formats German numbers with grouping and comma', () {
    expect(formatGermanNumber(2350), '2.350');
    expect(formatGermanNumber(81.54, digits: 1), '81,5');
    expect(formatGermanNumber(-0.4, digits: 1), '−0,4');
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

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Beide Übersichtskarten wie in der Tagesansicht von heute.
class _Overview extends StatelessWidget {
  const _Overview({required this.model, this.onWeight, this.onTraining});

  final ProgressViewModel model;
  final VoidCallback? onWeight;
  final VoidCallback? onTraining;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => GainerScaffold(
      title: 'Kalender',
      children: [
        TodayWeightOverview(viewModel: model, today: _today(), onTap: onWeight),
        const SizedBox(height: 16),
        TodayTrainingOverview(viewModel: model, onTap: onTraining),
      ],
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProgressViewModel model, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  VoidCallback? onWeight,
  VoidCallback? onTraining,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: GainerTheme.forBrightness(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: _Overview(model: model, onWeight: onWeight, onTraining: onTraining),
    ),
  );
  unawaited(model.load());
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

class _DashboardApi extends ApiClient {
  _DashboardApi(this.onLoad)
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
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
