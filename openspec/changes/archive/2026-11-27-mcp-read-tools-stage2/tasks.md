# Tasks

## 1. Abfragen

- [x] 1.1 `ITrainingPlanQueries` mit Übungsnamen, gemeinsamer Mapper `TrainingSnapshots` für Plan-Handler, Übungszusammenführung und Abfrage. Prüfung: `ConnectorFlowTests.AssistantReadsPlansCardioWaterTemplatesAndWorkoutSummariesOfItsOwnerOnly` (CI, Postgres).
- [x] 1.2 `ICardioSessionQueries` (Bereich und Einzelabruf), Pulskennzahlen in `CardioHeartRate`. Prüfung: derselbe Test und `CardioSessionTests.HeartRateFiguresSkipSamplesWithoutSignal`.
- [x] 1.3 `IWaterIntakeQueries` und `INutritionDayTemplateQueries`. Prüfung: derselbe Integrationstest.
- [x] 1.4 `ExerciseCatalogFilter` um Kategorie, Archiv und „ohne Muskeln“ erweitert. Prüfung: derselbe Integrationstest, bestehende `ExerciseCatalog*Tests` (CI).
- [x] 1.5 `IWorkoutHistoryQueries.ListAsync` mit Bereich lokaler Starttage und Ausgangsplan. Prüfung: derselbe Integrationstest.
- [x] 1.6 `IWorkoutSummaryQueries` über `TrainingStatistics.Summarize`, `TrainingStatistics.Counts` als Port von `workoutCounts`. Prüfung: `WorkoutCountsTests` und derselbe Integrationstest.

## 2. Tools

- [x] 2.1 Tools `list_training_plans`, `get_training_plan`, `get_workout_summary`, `list_cardio_sessions`, `get_cardio_session`, `get_water`, `list_day_templates` registriert, `search_exercises` und `list_workouts` erweitert. Prüfung: `ConnectorFlowTests` (Tool-Liste, fremde IDs, Bereichsgrenzen).

## 3. Spec

- [x] 3.1 `openspec validate mcp-read-tools-stage2 --strict` und nach dem Archivieren `openspec validate --specs --strict` grün.
