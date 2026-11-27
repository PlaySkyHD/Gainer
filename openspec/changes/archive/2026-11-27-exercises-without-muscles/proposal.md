# Proposal

## Why

Die Muskelübersicht listet unter „Ohne Muskeln“ nur Übungen, die in der gewählten Ansicht vorkommen (aktive Pläne oder Trainings der letzten 7 bzw. 28 Tage). Eigene Übungen ohne Muskeln, die in keinem Plan stehen und nicht kürzlich trainiert wurden, findet der Nutzer nirgends. Er erwartete sie in der Muskelübersicht.

## What Changes

- Die Übungsverwaltung erhält den Schalter „Nur ohne Muskeln“.
- Die Muskelübersicht zeigt die Zeile „Alle Übungen ohne Muskeln“ mit der Anzahl nicht archivierter Übungen ohne Haupt- und Hilfsmuskeln. Sie öffnet die Übungsverwaltung mit eingeschaltetem Filter. Ohne solche Übungen zeigt sie „Keine“ und ist nicht antippbar.
- Nach der Rückkehr lädt die Muskelübersicht neu, damit eingetragene Muskeln sofort zählen.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `exercise-catalog`: neue Anforderung „Übungen ohne Muskeln finden“.

## Impact

`CatalogExercise.hasNoMuscles`, `ExerciseLibraryViewModel`, `ExerciseLibraryScreen`, `MuscleMapViewModel`, `MuscleMapScreen`, Goldens der Muskelübersicht. Kein Backend, kein Sync.
