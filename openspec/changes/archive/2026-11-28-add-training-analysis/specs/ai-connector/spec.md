## ADDED Requirements

### Requirement: Trainingsanalyse über MCP

Der MCP-Server SHALL das lesende Tool `get_training_analysis(period, exerciseId?)` anbieten, das die Trainingsanalyse der App für 4 Wochen, 3 Monate (Standard) oder 1 Jahr bis heute liefert: je Übung Einheiten, Trends, Status, Ermüdungssignale und Empfehlung mit Begründungstext sowie den Gesamtteil. Die Beschreibung MUST die Regeln und Schwellen nennen und sagen, dass die Empfehlungen keine medizinische Beratung sind.

#### Scenario: Analyse des Nutzers
- **GIVEN** Nutzer A hat eine eigene Übung in drei Trainings gesteigert, zuletzt 3 × 12 bei 65 kg, Nutzer B hat eine eigene Übung trainiert
- **WHEN** die verbundene App von Nutzer A `get_training_analysis` aufruft
- **THEN** enthält die Antwort nur die Übung von A mit Status `Progressing` und der Empfehlung `IncreaseWeight` auf 67,5 kg

#### Scenario: Fremde Übung und unbegrenzter Zeitraum
- **WHEN** die verbundene App von Nutzer A `get_training_analysis` mit der Übung von B oder mit dem Zeitraum `all` aufruft
- **THEN** meldet das Tool einen Fehler statt Daten
