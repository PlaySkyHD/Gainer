# Proposal

## Why

Der Nutzer möchte über ChatGPT alles abfragen können, was er in der App sieht. Nach Stufe 2 fehlen dem MCP-Server die Zahlen, die nur die App rechnet: die Verlaufskacheln der Trainingsstatistik, die Heatmap der Trainingstage, die Muskelkarte (geplant und trainiert), die Kennzahlen einer Cardio-Einheit und der Ernährungsdurchschnitt. Diese dritte Stufe portiert die Dart-Berechnungen nach C# und sichert über gemeinsame Fixtures, dass App und Server dieselben Werte liefern.

## What Changes

- Ports in `Gainer.Core` (rein, ohne Datenzugriff):
  - `TrainingTrends` aus `training_trends.dart` (`workoutTrendEntries`, `TrainingTrends.compute`), auf Basis von `TrainingStatistics.WorkoutBlocks`
  - `TrainingHeatmap` aus `training_heatmap.dart` (`buildTrainingHeatmap`, `heatmapBounds`, `heatmapLevel`)
  - `MuscleVolume` aus `muscle_volume.dart` (`MuscleVolume.fromPlans/fromWorkouts`, `MuscleLevel.of`)
  - `CardioAnalysis` aus `cardio_analysis.dart` (`CardioAnalysis.of/fromSeries`, `rmssd` mit Artefaktfilter) und `recoveryDropBpm`
  - `NutritionAverages` aus `nutrition_averages.dart` (`NutritionAverages.compute`)
- Neue Core-Abfrage `ITrainingAnalysisQueries` mit Implementierung in `Gainer.Infrastructure`; das Laden beendeter Trainings und der Übungsfaktoren teilen sich `InsightQueries` und die neue Abfrage.
- Neue lesende Tools `get_training_trends(period, includeWarmups)`, `get_training_heatmap()`, `get_muscle_volume(source, planId, period)`, `get_nutrition_averages(days)`; `get_cardio_session` liefert zusätzlich die Kennzahlen der Detailansicht.
- Gemeinsame Fixtures `contracts/fixtures/training-trends.json`, `training-heatmap.json`, `muscle-volume.json`, `cardio-analysis.json` und `nutrition-averages.json` mit Dart- und C#-Tests.

## Grenzen

- Pulszonen, Wochenziel und Maximalpuls liegen nur auf dem Telefon. Zeit und Anteil im Zielbereich nutzen deshalb den mit der Einheit gespeicherten Zielbereich bzw. die Phasen; der Cardio-Fortschritt (`CardioProgress`) ist nicht verfügbar.
- Die automatische Tagesart aus dem Trainingsrhythmus wird nur in der App projiziert. Der Ernährungsdurchschnitt nutzt das Ruhetag-Ziel nur an Tagen, die ausdrücklich als Ruhetag festgelegt sind, sonst das Trainingstag-Ziel.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `ai-connector`: Anforderung „Lesende Tools“ nennt die neuen Bereiche und erhält Szenarien für die neuen Tools.
- `training-statistics`: neue Anforderung, dass App und Server diese Kennzahlen gleich rechnen (Fixture-Parität).

## Impact

`Gainer.Core` (neue Ports und `ITrainingAnalysisQueries`), `Gainer.Infrastructure/Persistence` (`TrainingAnalysisQueries`, `TrainingInputQueries`, Registrierung), `Gainer.Api/Mcp` (neue Klasse `GainerStatisticsTools`, erweitert `GainerCardioTools`, `GainerNutritionTools`), `GainerConnectorExtensions`, Tests in `Gainer.UnitTests`, `Gainer.IntegrationTests` und `apps/mobile/test`. Keine Migration, kein Sync, keine HTTP-Verträge, keine Änderung am App-Code.
