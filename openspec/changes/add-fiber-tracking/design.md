# Design

Ballaststoffe folgen in Datenmodell, Sync und Anzeige dem Muster von `add-salt-tracking`. Abweichungen stehen ausdrücklich unten.

## D1 Optional wie Salz

`NutritionPer100Grams` und `NutritionTotals` erhalten `FiberGrams` als optionales letztes Feld, Standard `null`.
- Berechnen, Skalieren und Summieren behandeln Ballaststoffe wie Salz. Die Tagessumme enthält nur Einträge mit Angabe; ein leerer Wert zählt nicht als 0 g.
- Pro 100 g sind höchstens 100 g erlaubt; negative Werte sind ungültig.
- Gespeichert wird `FiberGrams` und `FiberGramsPerBasis` bei Einträgen und Tagesvorlagen-Einträgen (gemeinsame Basis `NutritionEntryValues`, inklusive `CopyValuesFrom`) sowie `FiberGrams` und `FiberGramsPer100Grams` bei Gerichtsbestandteilen.
- Selbst gesalzen (Salz-Eintrag) hat 0 g Ballaststoffe.

## D2 Ziel in der Zielphase

`NutritionTargetVersion.FiberGrams` ist nullable; `EffectiveFiberGrams` liefert dafür 30 g (DGE-Richtwert für Erwachsene).
- Bestehende Phasen bleiben `null`. Vergangene, unveränderliche Phasen ändern sich nicht, und der Abgleich `Matches` bleibt stabil.
- Das Formular zeigt den wirksamen Wert. Bleibt er bei 30 g und hatte die Phase keinen eigenen Wert, speichert die App weiterhin `null`.
- Gültige Werte liegen über 0 und höchstens bei 100 g.
- Der Fortschritt erhält `Fiber` gegen `EffectiveFiberGrams`.
- **Abweichung von Salz:** Das Ziel ist eine Untergrenze. Der Balken füllt sich bis zum Ziel und bleibt dann voll; es gibt keine Warnfarbe. Über dem Ziel zeigt die Zahl den echten Wert („34 / 30 g“).
- Das Ziel gilt für Trainings- und Ruhetage gleich; das optionale Ruhetag-Set bleibt unverändert.

## D3 Quellen

| Quelle | Regel |
| --- | --- |
| Open Food Facts | `fiber_100g` aus `nutriments`; über 100 g oder negativ → leer. Das Feld ist im bereits angefragten `nutriments` enthalten, die Feldliste ändert sich nicht. |
| Etiketten-Scan | Das Modell liefert `fiberGrams`, nur wenn gedruckt. Der Server skaliert wie die anderen Felder auf 100 g. Ballaststoffe sind für `canConfirm` nicht nötig. Parser `nutrition-label-v3`; `v2`-Antworten werden weiter gelesen. |
| KI-Schätzung | Jeder Bestandteil erhält `fiberGrams` (nullable im strikten Schema). Prompt-Regel: aus Referenzwerten schätzen, bei Unklarheit leer lassen statt raten. Schema `meal-estimate-v5`. |
| Manuell | Feld „Ballaststoffe“ (g pro 100 g) direkt unter Kohlenhydrate, wie auf dem Etikett. |

## D4 Anzeige

- **Tageskarte:** Die bestehende Salz-Zeile wird zur Zeile mit zwei Spalten „Ballaststoffe“ und „Salz“. Bei Textgröße 2 stehen beide untereinander.
- **Kalender:** wie die Tageskarte.
- **Durchschnitte:** „Ballaststoffe“ als Zeile in „Ø pro erfasstem Tag“, gemittelt über Tage mit Angabe; Tage innerhalb des Ziels zählen ab Erreichen der Untergrenze.
- **Zielphase:** Gruppe „Ballaststoffe mindestens“ mit DGE-Hinweis; die Zusammenfassung zeigt „Ballaststoffe ≥ 30 g“.
- **Prüfung von Schätzung und Etikett:** Ballaststoffe erscheinen wie Salz, nur wenn ein Wert vorliegt.
- Zahlen deutsch formatiert, eine Nachkommastelle nur, wenn nötig („12,5 g“, „30 g“).

## D5 Coach

`get_nutrition_summary` gibt je Tag und im Durchschnitt `fiberGrams` aus, wenn Angaben vorliegen. Das Backend berechnet den Wert; die AI interpretiert ihn nur.

## D6 Migration

Die Migration fügt nur Spalten hinzu, die leer sein dürfen, dazu Check-Constraints (`>= 0`, `<= 100` pro 100 g; Zielwert `> 0`, `<= 100`). Bestehende Daten bleiben unverändert. Nach `dotnet ef migrations add` mit `dotnet format` nachziehen.
