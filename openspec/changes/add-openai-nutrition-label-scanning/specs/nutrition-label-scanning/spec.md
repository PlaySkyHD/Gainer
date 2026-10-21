# nutrition-label-scanning

## ADDED Requirements

### Requirement: Nährwerttabelle per Foto lesen

Der Server SHALL ein Foto einer Nährwerttabelle mit dem OpenAI-Bildmodell lesen und kcal, Eiweiß, Kohlenhydrate und Fett pro 100 g als Vorschlag zurückgeben. Das Modell MUST nur gedruckte Werte mit Textbeleg liefern. Die Umrechnung auf 100 g MUST der Server deterministisch vornehmen. Ein Scan MUST NOT etwas speichern; erst die Bestätigung in der App legt einen Eintrag an.

#### Scenario: Etikett pro 100 g
- **GIVEN** ein Foto mit „Energie 1580 kJ / 377 kcal, Eiweiß 13,5 g“ pro 100 g
- **WHEN** die App das Foto an `/nutrition/label-scans` sendet
- **THEN** antwortet der Server mit Bezug `Per100Grams`, 377 kcal und 13,5 g Eiweiß pro 100 g, jeweils mit Status `Confirmed`, und `canConfirm` ist wahr

#### Scenario: Nur Portionswerte
- **GIVEN** ein Etikett mit 120 kcal pro Portion zu 30 g
- **WHEN** der Server das Etikett liest
- **THEN** meldet er 400 kcal pro 100 g mit Status `Converted` und Originalwert 120

#### Scenario: Portion ohne Gewicht
- **GIVEN** ein Etikett nur mit Werten pro Portion und ohne Portionsgewicht
- **WHEN** der Server das Etikett liest
- **THEN** sind die Werte pro 100 g leer und `canConfirm` ist falsch

### Requirement: Unplausible Werte und fehlende Tabelle

Der Server SHALL Werte über 950 kcal oder über 100 g Makro pro 100 g als `Implausible` markieren und `canConfirm` verweigern, wenn kcal fehlt oder die Makrosumme 105 g übersteigt. Zeigt das Foto keine Nährwerttabelle, SHALL der Server 422 mit `no_nutrition_label` antworten, und die App MUST einen verständlichen Hinweis zeigen.

#### Scenario: Fehllesung
- **GIVEN** das Modell liest 3770 kcal pro 100 g
- **WHEN** der Server die Antwort prüft
- **THEN** ist kcal `Implausible` und der Vorschlag kann nicht übernommen werden

#### Scenario: Kein Etikett
- **GIVEN** ein Foto eines Tellers
- **WHEN** die App es scannen lässt
- **THEN** zeigt sie „Auf dem Foto wurde keine Nährwerttabelle erkannt.“
