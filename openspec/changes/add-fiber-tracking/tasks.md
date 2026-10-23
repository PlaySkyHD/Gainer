# Tasks

## 1. Backend

- [x] 1.1 Ballaststoffe in `NutritionPer100Grams`/`NutritionTotals`, Berechnung, `NutritionEntryValues` inkl. `CopyValuesFrom`, Gerichte (D1); Unit-Tests für Skalierung, leere Werte und Grenzen.
- [x] 1.2 Ballaststoffziel in Zielphasen mit Standard 30 g, Fortschritt als Untergrenze (D2); Tests inkl. `Matches` für Altphasen.
- [x] 1.3 Migration `AddFiberTracking` mit `dotnet format`, Sync-Payloads, Verträge, OpenAPI (D6); Sync-Integrationstests mit zwei Testnutzern und Payload ohne Ballaststoffe.
- [x] 1.4 Open Food Facts `fiber_100g` (D3); Tests mit Fixture.
- [x] 1.5 Etiketten-Scan `nutrition-label-v3` mit Ballaststoffen, `v2` weiter lesbar (D3); Tests für pro Portion und fehlende Angabe.
- [x] 1.6 KI-Schätzung `meal-estimate-v5` mit `fiberGrams` (D3); Schema- und Parser-Tests.
- [x] 1.7 `get_nutrition_summary` mit Ballaststoffen (D5); Test des Tools. Die Nutzerbindung kommt aus den bestehenden Insight-Abfragen; Isolation der Ballaststoffwerte prüft der Sync-Integrationstest mit zwei Nutzern.

## 2. App

- [x] 2.1 `NutritionTotals.fiberGrams`, Sync-Codec, API-Modelle, Zielphase; Codec-Tests.
- [x] 2.2 Formularfeld, Etiketten- und Schätzungs-Prüfung (D3, D4); Tests.
- [x] 2.3 Tageskarte mit Zeile Ballaststoffe/Salz, Zielformular, Durchschnitte, Kalender (D4); Tests, Goldens, Vorschau bei Textgröße 1 und 2 (`tool/preview_goldens.sh`).

## 3. Abschluss

- [x] 3.1 `openspec validate add-fiber-tracking --strict`, lokal Build, Format, Unit-, Integrations- und Flutter-Tests grün.
- [ ] 3.2 CI-Checks im PR grün.
- [ ] 3.3 Deploy (Migration) und TestFlight; Barcode, Etikett, Schätzung und manuelle Eingabe auf dem iPhone prüfen.
