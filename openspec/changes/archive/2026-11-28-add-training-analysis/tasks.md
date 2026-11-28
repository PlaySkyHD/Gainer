# Tasks

## 1. Berechnung mit Fixture

- [x] 1.1 `TrainingAnalysis` in C# und Dart, Fixture `training-analysis.json` (Fortschritt mit Aufwärm-, gelöschten, laufenden und Trainings vor dem Zeitraum, Stagnation, Rückschritt mit allen Ermüdungssignalen, Körpergewichtsübungen mit kleinster Stufe, jeder Status und jede Empfehlung). Prüfung: `TrainingAnalysisFixtureTests` und `training_analysis_fixture_test.dart`.

## 2. Abfrage und Tool

- [x] 2.1 `ITrainingAnalysisQueries.AnalysisAsync` mit RepeatableRead-Transaktion; RIR und Blockname in den Trainingseingaben. Prüfung: `ConnectorFlowTests.AssistantReadsTrainingAnalysisOfItsOwnerOnly` (CI, Postgres).
- [x] 2.2 Tool `get_training_analysis` in `GainerAnalysisTools` registriert. Prüfung: derselbe Integrationstest (Tool-Liste, zwei Nutzer, fremde Übung, Zeitraum `all`).

## 3. App

- [x] 3.1 Screen „Trainingsanalyse“ mit ViewModel und Detail, Eintrag im Statistikbereich. Prüfung: `training_analysis_test.dart` (Öffnen, Liste, Zeitraum, Detail, leer, Textgröße 1,3 und 2,0) und `training_analysis_golden_test.dart`.

## 4. Spec

- [x] 4.1 `openspec validate add-training-analysis --strict` und nach dem Archivieren `openspec validate --specs --strict` grün.
