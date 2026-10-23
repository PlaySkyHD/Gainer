import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/nutrition/food_search.dart';
import '../../../domain/models/nutrition/nutrition.dart';

/// Lokaler Katalog allgemeiner Lebensmittel; sucht ohne Netz.
abstract interface class LocalFoodCatalog {
  /// Herkunft, die übernommene Einträge tragen.
  String get provider;

  Future<FoodSearchResult> search(String query);
}

/// Bundeslebensmittelschlüssel 4.0 als mitgeliefertes Asset. Wird beim ersten
/// Suchen einmal im Hintergrund geladen.
class BlsFoodCatalog implements LocalFoodCatalog {
  BlsFoodCatalog({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// Index ohne Asset, z. B. für Tests.
  BlsFoodCatalog.fromIndex(FoodSearchIndex index)
    : _bundle = null,
      _ready = index;

  static const asset = 'assets/food/bls_4_0.json';
  static const providerName = 'BLS 4.0';
  static const attribution =
      'Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), '
      'Version 4.0. https://doi.org/10.25826/Data20251217-134202-0. '
      'Lizenz: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). '
      'Auszug: kcal, Eiweiß, Kohlenhydrate, Fett, Ballaststoffe und Salz '
      'pro 100 g, auf zwei Nachkommastellen gerundet.';

  final AssetBundle? _bundle;
  FoodSearchIndex? _ready;
  Future<FoodSearchIndex>? _loading;

  @override
  String get provider => providerName;

  @override
  Future<FoodSearchResult> search(String query) async =>
      (_ready ?? await _load()).search(query);

  Future<FoodSearchIndex> _load() => _loading ??= () async {
    final text = await _bundle!.loadString(asset, cache: false);
    final index = await compute(parseBlsCatalog, text);
    _ready = index;
    return index;
  }();
}

/// Liest das Asset-Format von `tool/extract_bls.py`:
/// `foods` als `[code, name, kcal, protein, carbs, fat, fiber, salt]`.
FoodSearchIndex parseBlsCatalog(String source) {
  final json = jsonDecode(source);
  if (json is! Map<String, dynamic> || json['foods'] is! List) {
    throw const FormatException('Ungültiger Lebensmittelkatalog.');
  }
  double? value(Object? raw) => raw is num ? raw.toDouble() : null;
  final foods = <LocalFood>[];
  for (final row in json['foods'] as List) {
    if (row is! List || row.length != 8) {
      throw const FormatException('Ungültiger Lebensmitteleintrag.');
    }
    final kcal = value(row[2]);
    if (row[0] is! String || row[1] is! String || kcal == null) continue;
    foods.add(
      LocalFood(
        code: row[0] as String,
        name: row[1] as String,
        per100Grams: NutritionTotals(
          kilocalories: kcal,
          proteinGrams: value(row[3]),
          carbohydrateGrams: value(row[4]),
          fatGrams: value(row[5]),
          fiberGrams: value(row[6]),
          saltGrams: value(row[7]),
        ),
      ),
    );
  }
  return FoodSearchIndex(foods);
}
