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

## D5 Selbst gesalzen

Eigenes Salz ist ein normaler Eintrag:
- Name „Salz“, 0 kcal, 0 g Makros, 100 g Salz pro 100 g. Die Menge in Gramm ist damit gleich der Salzmenge.
- So läuft es ohne neues Datenmodell durch Tagessumme, Sync, Gerichte, „Zuletzt verwendet“ und Bearbeiten.
- Damit das geht, erlauben Server, Datenbank und App für Einträge und Bestandteile jetzt 0 kcal (vorher > 0). Negative Werte bleiben ungültig. Zielphasen, Schätzungen und Etiketten verlangen weiterhin mehr als 0 kcal.
- Open Food Facts akzeptiert ausdrücklich 0 kcal (z. B. Speisesalz); fehlende Energie bleibt `product_incomplete`.
- Schnellwahl: Prise 0,5 g, halber Teelöffel 3 g, Teelöffel 6 g, dazu eine eigene Menge von über 0 bis 100 g.

## D6 Migration

Die Migration fügt nur Spalten hinzu, die leer sein dürfen, dazu eigene Check-Constraints. Bestehende Daten bleiben unverändert. Der Test `AdditiveMigrationPreservesExistingNutritionDaySnapshot` schreibt seine Altdaten jetzt per SQL ins ursprüngliche Schema, weil das aktuelle Modell die neuen Spalten erwartet.
