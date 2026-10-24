import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/models/api/api_models.dart';
import 'package:gainer_mobile/data/repositories/body/body_repository.dart';
import 'package:gainer_mobile/data/repositories/cardio/cardio_repository.dart';
import 'package:gainer_mobile/data/repositories/health/health_steps_sync.dart';
import 'package:gainer_mobile/data/repositories/insights/insights_repository.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/training/training_log_repository.dart';
import 'package:gainer_mobile/data/services/api/api_client.dart';
import 'package:gainer_mobile/domain/models/cardio/cardio_session.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_plan_model.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_screen.dart';
import 'package:gainer_mobile/ui/features/calendar/calendar_view_model.dart';
import 'package:gainer_mobile/ui/features/progress/progress_view_model.dart';
import 'package:gainer_mobile/ui/features/training/active_workout_controller.dart';

import '../training/training_plans_test_support.dart';
import '../training/training_test_support.dart';

/// Donnerstag, 22. Oktober 2026, 10 Uhr UTC: in allen üblichen Zeitzonen
/// derselbe Kalendertag.
final calendarNow = DateTime.utc(2026, 10, 22, 10);

/// Lokale Repositories über einer gemeinsamen In-Memory-Datenbank.
class CalendarHarness {
  CalendarHarness._(this.training, this.cardio, this.nutrition, this.body);

  final TrainingHarness training;
  final CardioRepository cardio;
  final NutritionRepository nutrition;
  final BodyRepository body;
  var _ids = 5000;

  TrainingLogRepository get repository => training.repository;

  static Future<CalendarHarness> create({DateTime? now}) async {
    final training = await TrainingHarness.create(now: now ?? calendarNow);
    var cardioIds = 9000;
    return CalendarHarness._(
      training,
      CardioRepository(
        store: training.store,
        ids: () => testId(cardioIds++),
        clock: () => training.now,
      ),
      NutritionRepository(
        store: training.store,
        clock: () => training.now,
        scheduleProjection: training.repository.readScheduleProjection,
      ),
      BodyRepository(store: training.store, clock: () => training.now),
    );
  }

  CalendarViewModel viewModel() => CalendarViewModel(
    training: repository,
    cardio: cardio,
    nutrition: nutrition,
  );

  /// Setzt die Uhr zurück auf [calendarNow] (Seeds verstellen sie).
  void resetClock() => training.now = calendarNow;

  Future<TrainingPlanModel> plan(String name) => seedPlan(training, name: name);

  /// Zyklus aus [slots] (null = Ruhetag), heute auf Slot [todayIndex].
  Future<void> cycle(List<String?> slots, {int todayIndex = 0}) async {
    resetClock();
    await repository.schedule.saveRhythm(
      mode: TrainingScheduleMode.cycle,
      slots: [for (final id in slots) TrainingScheduleSlot(planId: id)],
      todaySlotIndex: todayIndex,
    );
  }

  /// Feste Tage Mo–So, gültig ab [validFrom] (Standard: heute).
  Future<void> weekly(List<String?> slots, {LocalDay? validFrom}) async {
    final from = validFrom;
    training.now = from == null
        ? calendarNow
        : DateTime.utc(from.year, from.month, from.day, 10);
    await repository.schedule.saveRhythm(
      mode: TrainingScheduleMode.weekly,
      slots: [for (final id in slots) TrainingScheduleSlot(planId: id)],
    );
    resetClock();
  }

  /// Beendetes Training aus [plan] am Tag [date] um 10 Uhr UTC, 58 Minuten.
  Future<void> finishedFromPlan(TrainingPlanModel plan, LocalDay date) async {
    final start = DateTime.utc(date.year, date.month, date.day, 10);
    training.now = start;
    var workout = await repository.startFromPlan(plan.planId);
    workout = await repository.saveWorkout(
      workout.copyWith(
        exercises: [strengthBlock('Bankdrücken', 3, id: plan.planId)],
      ),
    );
    training.now = start.add(const Duration(minutes: 58));
    await repository.finishWorkout(workout.workoutId);
    resetClock();
  }

  Future<Workout> finishedEmpty(String title, LocalDay date) async {
    final start = DateTime.utc(date.year, date.month, date.day, 10);
    final workout = await training.seedWorkout(
      title: title,
      start: start,
      end: start.add(const Duration(minutes: 45)),
      blocks: [strengthBlock('Kreuzheben', 2, id: title)],
    );
    resetClock();
    return workout;
  }

  Future<void> checkIn(
    LocalDay date, {
    double weightKg = 82.4,
    int? steps,
    int? sleepMinutes,
  }) async {
    await body.saveCheckIn(
      localDate: date.toIso(),
      weightKg: weightKg,
      caloriesKcal: null,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
      steps: steps,
      sleepMinutes: sleepMinutes,
    );
  }

  Future<void> food(
    LocalDay date, {
    required double kcal,
    double? protein,
    double? carbs,
    double? fat,
  }) => nutrition.saveEntry(
    date.toIso(),
    NutritionEntry(
      entryId: testId(_ids++),
      meal: NutritionMeal.lunch,
      position: 0,
      productName: 'Mittagessen',
      brand: null,
      amountGrams: 100,
      per100Grams: NutritionTotals(
        kilocalories: kcal,
        proteinGrams: protein,
        carbohydrateGrams: carbs,
        fatGrams: fat,
      ),
      source: null,
    ),
  );

  Future<void> target({
    required String from,
    double kcal = 2600,
    double protein = 180,
    double carbs = 300,
    double fat = 80,
    NutritionDayTarget? rest,
  }) => nutrition.saveTargetSchedule(
    NutritionTargetSchedule(
      versions: [
        NutritionTargetVersion(
          targetVersionId: testId(_ids++),
          name: 'Aufbau',
          category: NutritionTargetCategory.custom,
          effectiveFrom: from,
          effectiveUntil: null,
          inputMode: NutritionTargetInputMode.grams,
          kilocalories: kcal,
          proteinGrams: protein,
          carbohydrateGrams: carbs,
          fatGrams: fat,
          proteinPercent: null,
          carbohydratePercent: null,
          fatPercent: null,
          restDay: rest,
        ),
      ],
    ),
  );

  Future<void> cardioOn(LocalDay date) async {
    final start = DateTime.utc(date.year, date.month, date.day, 17);
    const length = Duration(minutes: 32);
    training.now = start.add(length);
    await cardio.saveFinished(
      CardioSession(
        sessionId: cardio.newSessionId(),
        activityType: CardioActivityType.values.first,
        startedAtUtc: start,
        endedAtUtc: start.add(length),
        heartRateBpm: [
          for (var i = 0; i < length.inSeconds ~/ 5 + 1; i++) 125 + (i % 20),
        ],
        rrIntervalsMs: const [],
        createdAtUtc: start.add(length),
        updatedAtUtc: start.add(length),
      ),
    );
    resetClock();
  }

  Future<void> dispose() => training.dispose();
}

/// Erstellt den Harness außerhalb der Fake-Async-Zone eines Widget-Tests.
Future<CalendarHarness> createCalendarHarness(WidgetTester tester) async {
  final harness = await tester.runAsync(CalendarHarness.create);
  if (harness == null) throw StateError('Harness nicht erstellt.');
  addTearDown(() => tester.runAsync(harness.dispose));
  return harness;
}

final calendarToday = LocalDay(2026, 10, 22);

/// Dashboard-API ohne Netz: liefert feste Werte für die Heute-Inhalte.
class FakeDashboardApi extends ApiClient {
  FakeDashboardApi()
    : super(
        configuration: ApiConfiguration(
          apiOrigin: Uri.parse('http://127.0.0.1:5099'),
          allowInsecureLoopbackForDevelopment: true,
        ),
      );

  @override
  Future<ApiDashboardInsights> getDashboardInsights({
    int days = 30,
    DateTime? through,
  }) async {
    calls++;
    return calendarDashboard();
  }

  int calls = 0;
}

ProgressViewModel fakeOverview([FakeDashboardApi? dashboardApi]) {
  final api = dashboardApi ?? FakeDashboardApi();
  final model = ProgressViewModel(InsightsRepository(api));
  addTearDown(model.dispose);
  addTearDown(api.close);
  return model;
}

/// Gewicht heute 82,4 kg mit Verlauf, vier Trainings in sieben Tagen.
ApiDashboardInsights calendarDashboard() => const ApiDashboardInsights(
  asOfRevision: 7,
  from: '2026-09-23',
  through: '2026-10-22',
  weightSeries: [
    ApiWeightPoint(date: '2026-10-15', weightKg: 83.1),
    ApiWeightPoint(date: '2026-10-18', weightKg: 82.8),
    ApiWeightPoint(date: '2026-10-22', weightKg: 82.4),
  ],
  latestWeight: ApiWeightPoint(date: '2026-10-22', weightKg: 82.4),
  sevenDayWeight: ApiWeightInsights(
    unit: 'kg',
    expectedDays: 7,
    observedDays: 2,
    coverage: .29,
    averageKg: 82.6,
  ),
  weight: ApiWeightInsights(
    unit: 'kg',
    expectedDays: 30,
    observedDays: 3,
    coverage: .1,
    averageKg: 82.8,
    trendKgPerWeek: -0.4,
  ),
  nutrition: ApiNutritionInsights(
    expectedDays: 30,
    observedDays: 9,
    coverage: .3,
    mealDiaryDays: 9,
    legacyCheckInDays: 0,
    caloriesKcal: ApiMetricAverage(value: 2350, observedDays: 9),
    proteinGrams: ApiMetricAverage(value: 145, observedDays: 9),
    carbohydrateGrams: ApiMetricAverage(observedDays: 9),
    fatGrams: ApiMetricAverage(observedDays: 9),
  ),
  training: ApiTrainingInsights(
    workoutCount: 12,
    volumeKgRepetitions: 42000,
    volumeAlgorithmVersion: 'training-volume-v2',
    estimatedOneRepMaxAlgorithmVersion: 'e1rm-epley-v2',
    volumeUnit: 'kg-repetitions',
    bestSet: null,
    bodyweightMissing: false,
  ),
  workoutsLast7Days: 4,
);
Future<void> pumpCalendar(
  WidgetTester tester,
  CalendarHarness harness, {
  ProgressViewModel? overview,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ValueChanged<MobileArea>? onOpenArea,
  ValueChanged<String>? onOpenNutritionDay,
  ValueChanged<String>? onOpenCheckInDay,
  HealthStepsSync? steps,
  Listenable? visibility,
  bool Function()? isVisible,
  Listenable? refresh,
  NutritionRepository? nutrition,
  LocalDay? Function()? takeRequestedDay,
}) async {
  final active = ActiveWorkoutController(harness.repository);
  addTearDown(active.dispose);
  await tester.pumpWidget(
    trainingTestApp(
      brightness: brightness,
      textScale: textScale,
      home: CalendarScreen(
        training: harness.repository,
        activeWorkout: active,
        cardioSessions: harness.cardio,
        nutrition: nutrition ?? harness.nutrition,
        overview: overview,
        onOpenArea: onOpenArea,
        onOpenNutritionDay: onOpenNutritionDay,
        onOpenCheckInDay: onOpenCheckInDay,
        steps: steps,
        visibility: visibility,
        isVisible: isVisible,
        takeRequestedDay: takeRequestedDay,
        refresh: refresh,
      ),
    ),
  );
  await settle(tester);
}

/// Tippt einen Tag im Monatskalender an. Er steht unten auf der Übersicht;
/// daher erst hinscrollen. Danach scrollt die Seite selbst zurück nach oben.
Future<void> tapDay(WidgetTester tester, LocalDay day) async {
  final cell = find.byKey(ValueKey('calendar-day-${day.toIso()}'));
  await tester.scrollUntilVisible(
    cell.hitTestable(),
    300,
    scrollable: find
        .descendant(
          of: find.byType(CalendarScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(cell);
  await settle(tester);
}

String dayLabel(WidgetTester tester, LocalDay day) => tester
    .widget<Semantics>(find.byKey(ValueKey('calendar-day-${day.toIso()}')))
    .properties
    .label!;
