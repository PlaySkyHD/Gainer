# Proposal

## Why

Eier, Brötchen oder Scheiben zählt man, statt sie zu wiegen. Bisher musste man für 4 Eier selbst 200 g ausrechnen und eintippen.

## What Changes

- Einträge und Gerichtsbestandteile haben optional ein **Stückgewicht** und eine **Stückzahl**. Die Grammzahl bleibt maßgeblich und ist bei gesetzter Stückzahl genau Stückzahl × Stückgewicht. Summen, Sync und alte Einträge bleiben unverändert.
- **Hinzufügen** (Zuletzt, Suche, Barcode): Unter „Menge“ steht „Anzahl“ mit Minus und Plus. Ergebnisse mit bekanntem Stückgewicht zeigen „1 Stk = 50 g“. Hat ein Lebensmittel kein Stückgewicht, erscheint ein Hinweis, die Menge in g einzugeben.
- **Formular** (manuell, Eintrag bearbeiten, Gerichtsbestandteil): Gruppe „Stück (optional)“ mit „Gewicht pro Stück“ und „Anzahl“. Daraus wird die Menge berechnet. Wer Gramm tippt, löscht die Anzahl.
- **Liste:** „Ei, gekocht · 4 Stk · 310 kcal“.
- **Quellen des Stückgewichts:**
  - Open Food Facts liefert die Portionsgröße (`serving_quantity` in g oder ml).
  - Die KI-Schätzung liefert `pieceCount` und `pieceGrams` bei gezählten Dingen („4 Eier“).
  - Das manuelle Feld „Gewicht pro Stück“.
  - Frühere Einträge über „Zuletzt verwendet“ und gespeicherte Gerichte, die beim Übernehmen die Stückzahl skalieren.
- Eingabefehler zeigt die App als Text statt als rohe `NutritionValidationException`.

## Capabilities

- **Neu:** `piece-counts`.

## Impact

- **Backend:**
  - `NutritionPortion`, Spalten `PieceGrams` und `PieceCount` in `nutrition_entries` und `reusable_meal_components` (Migration `AddNutritionPieces`), dazu Check-Constraints.
  - Sync-Payloads, optionale Vertragsfelder, Open-Food-Facts-Portionsgröße, KI-Schema `meal-estimate-v4`.
- **App:** Modell (lokal flach, vom Server als `portion`), Sync-Codec, „Zuletzt verwendet“, Gerichte, Formular, Anzahl beim Hinzufügen, Listenanzeige.
