# Proposal

## Why

Der Nutzer möchte über ChatGPT alles abfragen können, was er in der App sieht. Nach Stufe 1 fehlen dem MCP-Server noch Trainingspläne, Cardio-Einheiten, Wasser, Tagesvorlagen, die Trainingszusammenfassung und Filter für Übungen und Trainings. Diese zweite Stufe ergänzt einfache Abfragen auf Daten, die der Server bereits speichert.

## What Changes

- Neue lesende Tools:
  - `list_training_plans` (optional mit archivierten Plänen) und `get_training_plan`: Name, Notizen, Archiv-Status, Einträge mit Übung, Aufwärm- und Arbeitssätzen, Supersatz und Notiz
  - `list_cardio_sessions` (Standard 30 Tage, höchstens 366) und `get_cardio_session`: Typ, Vorlage, Zeiten, Dauer, Durchschnitts- und Maximalpuls aus der Pulsreihe, Strecke, Leistung, Energie, Notiz; im Detail Pulsreihe, RR-Intervalle, Phasen und Erholung
  - `get_water` (Standard heute, höchstens 366 Tage): Milliliter je Tag; das Tagesziel liegt nur auf dem Telefon
  - `list_day_templates`: Tagesvorlagen mit Einträgen und Summen
  - `get_workout_summary`: Dauer, gezählte Sätze, Wiederholungen, Volumen, bester Satz je Übung, neue Rekorde und „n. Training · m. diese Woche“
- `search_exercises` filtert nach Kategorie, archivierten Übungen und eigenen Übungen ohne Muskeln und liefert die Kategorien einmal mit.
- `list_workouts` filtert optional nach lokalen Starttagen (höchstens 366) und nennt den Ausgangsplan.
- Neue Core-Abfragen `ITrainingPlanQueries`, `ICardioSessionQueries`, `IWaterIntakeQueries`, `INutritionDayTemplateQueries`, `IWorkoutSummaryQueries`; `IWorkoutHistoryQueries` und `ExerciseCatalogFilter` werden abwärtskompatibel erweitert. `TrainingStatistics.Counts` portiert `workoutCounts` der App.
- Plan- und Cardio-Snapshots entstehen über einen gemeinsamen Mapper statt über Kopien in den Handlern.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `ai-connector`: Anforderung „Lesende Tools“ nennt die neuen Bereiche und Grenzen.

## Impact

`Gainer.Api/Mcp` (neue Klassen `GainerTrainingTools`, `GainerCardioTools`, erweitert `GainerMcpTools`, `GainerNutritionTools`), `GainerConnectorExtensions`, neue Queries in `Gainer.Core` und `Gainer.Infrastructure/Persistence`, `GainerPersistenceExtensions`. Keine Migration, kein Sync, keine HTTP-Verträge.
