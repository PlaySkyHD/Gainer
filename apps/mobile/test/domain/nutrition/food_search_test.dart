import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/data/repositories/nutrition/bls_food_catalog.dart';
import 'package:gainer_mobile/domain/models/nutrition/food_search.dart';

void main() {
  late final FoodSearchIndex index;

  setUpAll(() {
    index = parseBlsCatalog(File(BlsFoodCatalog.asset).readAsStringSync());
  });

  List<String> names(String query, {int take = 20}) =>
      index.search(query).foods.take(take).map((food) => food.name).toList();

  test('the asset contains the full BLS 4.0 with fiber and salt', () {
    expect(index.length, 7140);
    final oats = index.search('Hafer Flocken').foods.first;
    expect(oats.name, 'Hafer Flocken');
    expect(oats.per100Grams.kilocalories, 348);
    expect(oats.per100Grams.fiberGrams, 10.98);
  });

  test('compound words find the split BLS name', () {
    expect(names('Haferflocken', take: 3), contains('Hafer Flocken'));
    expect(
      names('Haehnchenbrust', take: 5),
      contains('Hähnchen Brust, ohne Haut, roh'),
    );
  });

  test('short words only match whole words or word ends', () {
    final eggs = names('Ei');
    expect(eggs, contains('Hühnerei roh'));
    expect(eggs, isNot(contains('Reis poliert, roh')));
  });

  test('a word start ranks above a match inside a word', () {
    final rice = names('Reis');
    expect(rice.first, startsWith('Reis'));
    expect(
      rice.indexOf('Reis poliert, roh'),
      lessThan(rice.contains('Erdbeereis') ? rice.indexOf('Erdbeereis') : 99),
    );
  });

  test('one typo, umlauts and plurals are tolerated', () {
    expect(names('Bananne', take: 3), contains('Banane roh'));
    expect(names('Bananen', take: 3), contains('Banane roh'));
    expect(names('Hühnerei', take: 3), contains('Hühnerei roh'));
    expect(names('huehnerei', take: 3), contains('Hühnerei roh'));
  });

  test('several words narrow the result and mark partial matches', () {
    final result = index.search('Banane roh');
    expect(result.foods.first.name, 'Banane roh');
    expect(result.partial, isFalse);
    expect(index.search('Banane xyzqwv').partial, isTrue);
  });

  test('too short or empty queries return nothing', () {
    expect(index.search('a').foods, isEmpty);
    expect(index.search('  ').foods, isEmpty);
    expect(index.search('xyzqwv').foods, isEmpty);
  });

  test('results are capped at 20', () {
    expect(index.search('roh').foods, hasLength(FoodSearchIndex.maxResults));
  });

  test('a search over the whole catalog stays fast', () {
    final watch = Stopwatch()..start();
    for (final query in ['Haferflocken', 'Ei', 'Reis', 'Bananne', 'Käse']) {
      index.search(query);
    }
    watch.stop();
    // Großzügig für Debug-Modus und CI; auf dem Gerät deutlich schneller.
    expect(watch.elapsedMilliseconds / 5, lessThan(250));
  });

  test('the shipped asset loads through the bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final catalog = BlsFoodCatalog();
    final result = await catalog.search('Banane');
    expect(result.foods.first.name, 'Banane roh');
    expect(catalog.provider, 'BLS 4.0');
  });

  test('normalization folds umlauts, ß and typed ae/oe/ue', () {
    expect(normalizeFoodText('Hähnchen-Brust, Soße'), 'hahnchen brust sosse');
    expect(normalizeFoodText('Haehnchen'), 'hahnchen');
  });
}
