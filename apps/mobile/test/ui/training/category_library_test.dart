import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/features/training/category_library_view_model.dart';

import 'exercise_catalog_test_support.dart';

void main() {
  late CatalogHarness harness;
  late CategoryLibraryViewModel viewModel;

  setUp(() async {
    harness = await CatalogHarness.create();
    viewModel = CategoryLibraryViewModel(repository: harness.repository);
  });

  tearDown(() async {
    viewModel.dispose();
    await harness.dispose();
  });

  test('Basiskategorien sind nur lesbar', () async {
    await viewModel.load();

    expect(viewModel.baseCategories.map((c) => c.name), ['Beine', 'Brust']);
    expect(viewModel.ownCategories, isEmpty);
    final error = await viewModel.save(
      name: 'Umbenannt',
      categoryId: 'base-chest',
    );
    expect(error, isNotNull);
    await viewModel.load();
    expect(viewModel.baseCategories.map((c) => c.name), contains('Brust'));
  });

  test('eigene Kategorie anlegen und umbenennen', () async {
    expect(await viewModel.save(name: 'Reha'), isNull);
    await viewModel.load();
    final created = viewModel.ownCategories.single;
    expect(created.name, 'Reha');

    expect(
      await viewModel.save(name: 'Mobilität', categoryId: created.id),
      isNull,
    );
    await viewModel.load();

    expect(viewModel.ownCategories.single.id, created.id);
    expect(viewModel.ownCategories.single.name, 'Mobilität');
  });

  test('archivierte Kategorie verschwindet, zugeordnete Übungen bleiben unverändert', () async {
    await viewModel.save(name: 'Reha');
    await viewModel.load();
    final category = viewModel.ownCategories.single;
    final exercise = await seedOwnExercise(
      harness,
      name: 'Band-Zug',
      categoryIds: [category.id],
    );
    final before = (await harness.repository.readExercises()).singleWhere(
      (item) => item.id == exercise.id,
    );

    final error = await viewModel.archive(category.id);

    expect(error, isNull);
    await viewModel.load();
    expect(viewModel.ownCategories, isEmpty);
    final categories = await harness.repository.readCategories(
      includeArchived: true,
    );
    expect(
      categories.singleWhere((item) => item.id == category.id).isArchived,
      isTrue,
    );
    final after = (await harness.repository.readExercises()).singleWhere(
      (item) => item.id == exercise.id,
    );
    expect(after, before);
    expect(after.categoryIds, [category.id]);
  });
}
