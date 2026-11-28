# Proposal

## Why

ChatGPT hat über den MCP-Connector nach einem Tool gefragt, das für einen Zeitraum sagt, welche Übungen stagnieren, wo Gewicht oder Wiederholungen steigen, wie sich das Volumen entwickelt, ob es Zeichen übermäßiger Ermüdung gibt, und eine konkrete Empfehlung für das nächste Training gibt. Der Nutzer hat entschieden: Die Analyse kommt gleichzeitig in die App und den MCP-Server, beide rechnen identisch (gemeinsame Fixture), und das Ergebnis enthält Signale plus eine konkrete Empfehlung je Übung.

## What Changes

- Neue reine Berechnung `TrainingAnalysis` in Dart (`lib/domain/models/training/training_analysis.dart`) und C# (`Gainer.Core/Insights/TrainingAnalysis.cs`) auf Basis der vorhandenen Regeln aus `training-statistics.json` (Arbeitssätze ohne Aufwärmsätze, effektives Gewicht, Epley-1RM) und der Zeiträume des Verlaufs (4 W, 3 M, 1 J).
- Je Übung: Einheiten, Trends (erstes gegen letztes Drittel), Status `Progressing`/`Stagnating`/`Regressing`/`InsufficientData`, Ermüdungssignale mit Belegen und eine regelbasierte Empfehlung (`IncreaseWeight`, `IncreaseReps`, `KeepWeight`, `Deload`, `ChangeStimulus`, `NoRecommendation`) mit deutschem Begründungstext. Dazu ein Gesamtteil mit Wochenvolumen und Ermüdungs-Flag.
- Gemeinsame Fixture `contracts/fixtures/training-analysis.json` mit Dart- und C#-Test.
- `ITrainingAnalysisQueries.AnalysisAsync` lädt Trainings, Check-ins und Katalogfaktoren in einer RepeatableRead-Transaktion; `TrainingSetInput` trägt dafür den RIR, `TrainingBlockInput` den Namen des Blocks.
- Neues lesendes MCP-Tool `get_training_analysis(period, exerciseId?)` in `GainerAnalysisTools`.
- App: neuer Screen „Trainingsanalyse“, erreichbar aus dem Statistikbereich unter „Muskeln“, mit Zeitraum-Umschalter, Gesamtteil, Übungsliste mit Status-Badge und Detail je Übung. Die Daten kommen offline aus dem lokalen Speicher.

## Grenzen

- Trainingsplan-Einträge haben kein Ziel für Wiederholungsbereich oder Gewicht. Der Wiederholungsbereich der doppelten Progression wird deshalb aus dem besten Topsatz der letzten Einheit abgeleitet.
- Zeitbasierte Übungen gibt es nicht; Körpergewichtsübungen (mit und ohne Zusatzgewicht, assistiert) sind abgedeckt.
- Die Empfehlungen sind regelbasierte Vorschläge, keine medizinische Beratung.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `training-statistics`: neue Anforderungen für Screen, Status, Ermüdungssignale und Empfehlung; „Gleiche Kennzahlen in App und Server“ umfasst die Trainingsanalyse.
- `ai-connector`: neue Anforderung für das Tool `get_training_analysis`.

## Impact

`Gainer.Core/Insights` (`TrainingAnalysis`, `ITrainingAnalysisQueries`, optionale Felder an `TrainingSetInput` und `TrainingBlockInput`), `Gainer.Infrastructure/Persistence` (`TrainingAnalysisQueries`, `TrainingInputQueries`), `Gainer.Api/Mcp` (`GainerAnalysisTools`, Registrierung), App (`training_analysis.dart`, Screen und ViewModel, Eintrag im Statistikbereich), Tests in `Gainer.UnitTests`, `Gainer.IntegrationTests` und `apps/mobile/test`. Keine Migration, kein Sync, keine HTTP-Verträge.
