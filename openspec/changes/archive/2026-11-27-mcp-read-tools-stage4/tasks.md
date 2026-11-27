# Tasks

## 1. Port mit Fixture

- [x] 1.1 `TrainingScheduleProjection` portiert, Fixture `training-schedule.json` (ohne Rhythmus, Zyklus mit Status und Tagesgrenze, Anker nach Gültig-ab mit Verschiebungen und archiviertem bzw. unbekanntem Plan, feste Tage mit Ausnahmen, feste Tage ohne sieben Slots, heute erledigt um die Sommerzeit). Prüfung: `TrainingScheduleFixtureTests` und `training_schedule_fixture_test.dart`.
- [x] 1.2 `NutritionAverages` nutzt die automatische Tagesart. Prüfung: `NutritionAveragesFixtureTests`.

## 2. Abfrage und Tools

- [x] 2.1 `ITrainingScheduleQueries` mit `TrainingScheduleQueries` registriert. Prüfung: `ConnectorFlowTests.AssistantReadsTrainingScheduleTodayAndDayTargetsOfItsOwnerOnly` (CI, Postgres).
- [x] 2.2 Tools `get_training_schedule` und `get_training_today` registriert, `get_nutrition_days` und `get_nutrition_averages` wählen das Ziel über die Rhythmus-Vorschau. Prüfung: derselbe Integrationstest (Tool-Liste, zwei Nutzer, Bereichsfehler) und der angepasste Stufe-3-Test.

## 3. Spec

- [x] 3.1 `openspec validate mcp-read-tools-stage4 --strict` und nach dem Archivieren `openspec validate --specs --strict` grün.
