import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/nutrition_repository.dart';
import 'package:gainer_mobile/data/repositories/sync/local_sync_store.dart';
import 'package:gainer_mobile/data/services/local/local_database.dart';
import 'package:gainer_mobile/domain/models/nutrition/nutrition.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_day_templates.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_screen.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_targets_editor.dart';
import 'package:gainer_mobile/ui/features/nutrition/nutrition_view_model.dart';

import '../training/training_test_support.dart';

const accountId = '00000000-0000-4000-8000-000000000008';

final _version = NutritionTargetVersion(
  targetVersionId: '00000000-0000-4000-8000-000000000061',
  name: 'Ziele',
  category: NutritionTargetCategory.custom,
  effectiveFrom: '2026-10-01',
  effectiveUntil: null,
  inputMode: NutritionTargetInputMode.grams,
  kilocalories: 2600,
  proteinGrams: 180,
  carbohydrateGrams: 290,
  fatGrams: 80,
  proteinPercent: null,
  carbohydratePercent: null,
  fatPercent: null,
  restDay: const NutritionDayTarget(
    inputMode: NutritionTargetInputMode.percent,
    kilocalories: 2200,
    proteinGrams: 165,
    carbohydrateGrams: 220,
    fatGrams: 73.33,
    proteinPercent: 30,
    carbohydratePercent: 40,
    fatPercent: 30,
  ),
);

void _size(WidgetTester tester, double height) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final variant in const [
    (name: 'light', brightness: Brightness.light, scale: 1.0, height: 1500.0),
    (name: 'dark', brightness: Brightness.dark, scale: 1.0, height: 1500.0),
    (
      name: 'scale2_light',
      brightness: Brightness.light,
      scale: 2.0,
      height: 2600.0,
    ),
  ]) {
    testWidgets('targets editor ${variant.name}', (tester) async {
      _size(tester, variant.height);
      await tester.pumpWidget(
        trainingTestApp(
          brightness: variant.brightness,
          textScale: variant.scale,
          home: GainerSheetFrame(
            child: NutritionTargetsEditor(
              current: _version,
              hasSchedule: false,
              onSetUpSchedule: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile(
          'goldens/nutrition_targets_editor_${variant.name}.png',
        ),
      );
    }, tags: ['golden']);
  }

  for (final variant in const [
    (name: 'light', brightness: Brightness.light),
    (name: 'dark', brightness: Brightness.dark),
  ]) {
    testWidgets('rest day card ${variant.name}', (tester) async {
      _size(tester, 900);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = NutritionRepository(
        store: LocalSyncStore(database: database, accountId: accountId),
        clock: () => DateTime.utc(2026, 10, 12, 10),
        scheduleProjection: () async => TrainingScheduleProjection(
          schedule: null,
          plans: const [],
          workouts: const [],
          today: LocalDay(2026, 10, 12),
        ),
      );
      await tester.runAsync(() async {
        await repository.saveTargetSchedule(
          NutritionTargetSchedule(versions: [_version]),
        );
        await repository.saveEntry(
          '2026-10-12',
          NutritionEntry(
            entryId: '00000000-0000-4000-8000-000000000301',
            meal: NutritionMeal.breakfast,
            position: 0,
            productName: 'Haferflocken',
            brand: null,
            amountGrams: 80,
            per100Grams: const NutritionTotals(
              kilocalories: 370,
              proteinGrams: 13,
              carbohydrateGrams: 59,
              fatGrams: 7,
            ),
            source: null,
          ),
        );
      });
      final viewModel = NutritionViewModel(
        repository: repository,
        localDate: '2026-10-12',
      );
      await tester.pumpWidget(
        trainingTestApp(
          brightness: variant.brightness,
          home: NutritionScreen(viewModel: viewModel),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ruhetag'), findsOneWidget);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/nutrition_rest_day_${variant.name}.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('save template sheet light', (tester) async {
    _size(tester, 700);
    await tester.pumpWidget(
      trainingTestApp(
        home: const GainerSheetFrame(child: SaveTemplateSheet(templates: [])),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CupertinoApp),
      matchesGoldenFile('goldens/nutrition_save_template_light.png'),
    );
  }, tags: ['golden']);
}
