import '../../../domain/models/nutrition/nutrition.dart';

/// Speicherziel des gemeinsamen Lebensmittel-Hinzufügen-Dialogs. Die Erfassung
/// (Suche, Barcode, Zuletzt, Manuell, ...) ist für alle Ziele identisch, nur
/// das Ergebnis landet an einem anderen Ort.
sealed class FoodAddTarget {
  const FoodAddTarget();
}

/// Das Lebensmittel wird als Nutrition Entry in eine Mahlzeit des gewählten
/// Tages geschrieben.
final class DayMealTarget extends FoodAddTarget {
  const DayMealTarget();
}

/// Das Lebensmittel wird als Bestandteil an einen lokalen Gerichtsentwurf
/// zurückgegeben. Ein Ernährungstag wird dabei nicht verändert.
final class MealDraftTarget extends FoodAddTarget {
  const MealDraftTarget();
}

/// Validiertes Lebensmittel als Snapshot, noch ohne Zielzuordnung. Daraus
/// entsteht je nach [FoodAddTarget] ein Eintrag oder ein Gerichtsbestandteil.
class FoodComponentDraft {
  const FoodComponentDraft({
    required this.name,
    required this.brand,
    required this.amountGrams,
    required this.per100Grams,
    required this.source,
  });

  final String name;
  final String? brand;
  final double amountGrams;
  final NutritionTotals per100Grams;
  final NutritionSource? source;

  /// Prüft die Werte wie ein Gerichtsbestandteil und liefert eine kurze
  /// Fehlermeldung, oder `null`, wenn der Draft gültig ist.
  String? validate() {
    if (name.trim().isEmpty) return 'Bitte einen Namen eingeben.';
    if (!amountGrams.isFinite || amountGrams <= 0 || amountGrams > 100000) {
      return 'Die Menge muss zwischen 0 und 100.000 g liegen.';
    }
    if (!per100Grams.kilocalories.isFinite || per100Grams.kilocalories <= 0) {
      return 'Die Kalorien müssen größer als 0 sein.';
    }
    final macros = [
      per100Grams.proteinGrams,
      per100Grams.carbohydrateGrams,
      per100Grams.fatGrams,
      per100Grams.saltGrams,
    ];
    if (macros.any((value) => value != null && value < 0)) {
      return 'Nährwerte dürfen nicht negativ sein.';
    }
    if ((per100Grams.saltGrams ?? 0) > 100) {
      return 'Salz kann höchstens 100 g pro 100 g betragen.';
    }
    return null;
  }

  /// Erzeugt den unabhängigen Gerichtsbestandteil an [position].
  ReusableMealComponent toComponent({
    required String componentId,
    required int position,
  }) => ReusableMealComponent(
    componentId: componentId,
    position: position,
    name: name,
    brand: brand,
    amountGrams: amountGrams,
    per100Grams: per100Grams,
    source: source,
  );
}
