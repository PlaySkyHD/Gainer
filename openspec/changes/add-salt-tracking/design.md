# Design

## D1 Optional wie die Makros

`NutritionPer100Grams` und `NutritionTotals` erhalten `SaltGrams` als optionales letztes Feld, Standard `null`.
- Berechnen, Skalieren und Summieren behandeln Salz wie Eiweiß, Kohlenhydrate und Fett. Die Tagessumme enthält nur Einträge mit Salzangabe.
- Pro 100 g sind höchstens 100 g Salz erlaubt; negative Werte sind ungültig.
- Gespeichert wird wie bei den Makros: `SaltGrams` und `SaltGramsPerBasis` bei Einträgen, `SaltGrams` und `SaltGramsPer100Grams` bei Gerichtsbestandteilen.

## D2 Obergrenze in der Zielphase

`NutritionTargetVersion.SaltGrams` ist nullable; `EffectiveSaltGrams` liefert dafür 6 g.
- Bestehende Phasen bleiben `null`. So ändern sich vergangene, unveränderliche Phasen nicht, und der Abgleich `Matches` bleibt stabil.
- Das Formular zeigt den wirksamen Wert. Bleibt er bei 6 g und hatte die Phase keinen eigenen Wert, speichert die App weiterhin `null`.
- Gültige Werte liegen über 0 und höchstens bei 100 g.
- Der Fortschritt erhält `Salt` gegen `EffectiveSaltGrams`.

## D3 Quellen

| Quelle | Regel |
| --- | --- |
| Open Food Facts | `salt_100g`, sonst `sodium_100g × 2,5`; über 100 g → leer |
| Etiketten-Scan | Das Modell liefert `saltGrams` und `sodiumGrams` getrennt, nur was gedruckt ist. Der Server rechnet Natrium × 2,5 um (Status `Converted`) und skaliert wie die anderen Felder. Salz ist für `canConfirm` nicht nötig. Parser `nutrition-label-v2`. |
| Manuell | Feld „Salz“ (g pro 100 g) unter Fett |

## D4 Anzeige

- **Tageskarte:** eine eigene Zeile „Salz“ unter Protein, Kohlenhydrate und Fett. Sie ist so breit wie eine Spalte, damit vier Spalten bei großer Schrift nicht überlaufen.
- **Kalender:** wie die Tageskarte; bei großer Schrift untereinander.
- **Durchschnitte:** „Salz“ als vierte Zeile in „Ø pro erfasstem Tag“, gemittelt über Tage mit Salzangabe.
- **Zielphase:** eigene Gruppe „Salz höchstens“ mit DGE-Hinweis; die Zusammenfassung zeigt „Salz ≤ 6 g“.

## D5 Migration

Die Migration fügt nur Spalten hinzu, die leer sein dürfen, dazu eigene Check-Constraints. Bestehende Daten bleiben unverändert. Der Test `AdditiveMigrationPreservesExistingNutritionDaySnapshot` schreibt seine Altdaten jetzt per SQL ins ursprüngliche Schema, weil das aktuelle Modell die neuen Spalten erwartet.
