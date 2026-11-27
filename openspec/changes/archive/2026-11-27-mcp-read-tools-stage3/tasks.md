# Tasks

## 1. Ports mit Fixtures

- [x] 1.1 `TrainingTrends` portiert, Fixture `training-trends.json` (DST-Wochengrenze, Monatsgrenze, Aufwärmsätze, leere Abschnitte, fehlendes Körpergewicht, „Alle“ ohne Daten). Prüfung: `TrainingTrendsFixtureTests` und `training_trends_fixture_test.dart`.
- [x] 1.2 `TrainingHeatmap` portiert, Fixture `training-heatmap.json` (Sommerzeit, Einheit über Mitternacht, negative Dauer, Schaltjahr, gleich lange Tage, leer). Prüfung: `TrainingHeatmapFixtureTests` und `training_heatmap_fixture_test.dart`.
- [x] 1.3 `MuscleVolume` portiert, Fixture `muscle-volume.json` (archivierte Pläne, Stufengrenzen, Zeitfenster, Aufwärm- und unvollständige Sätze, unbekannte Übung). Prüfung: `MuscleVolumeFixtureTests` und `muscle_volume_fixture_test.dart`.
- [x] 1.4 `CardioAnalysis` portiert, Fixture `cardio-analysis.json` (Zielzone, Phasen, RR-Artefakte, Mindestzahl der Differenzen, Sprung an der Grenze, Erholung). Prüfung: `CardioAnalysisFixtureTests` und `cardio_analysis_fixture_test.dart`.
- [x] 1.5 `NutritionAverages` portiert, Fixture `nutrition-averages.json` (heute leer, Zielwechsel, Ruhetag-Ziel, Grenze ±10 %, ohne Ziel, ohne Einträge). Prüfung: `NutritionAveragesFixtureTests` und `nutrition_averages_fixture_test.dart`.

## 2. Abfragen und Tools

- [x] 2.1 `ITrainingAnalysisQueries` mit `TrainingAnalysisQueries`; gemeinsames Laden in `TrainingInputQueries`. Prüfung: `ConnectorFlowTests.AssistantReadsTrendsHeatmapMuscleVolumeCardioMetricsAndNutritionAveragesOfItsOwnerOnly` (CI, Postgres) und die bestehenden `InsightQueries`-Tests (CI).
- [x] 2.2 Tools `get_training_trends`, `get_training_heatmap`, `get_muscle_volume`, `get_nutrition_averages` registriert, `get_cardio_session` um Kennzahlen erweitert. Prüfung: derselbe Integrationstest (Tool-Liste, zwei Nutzer, Argumentfehler).

## 3. Spec

- [x] 3.1 `openspec validate mcp-read-tools-stage3 --strict` und nach dem Archivieren `openspec validate --specs --strict` grün.
