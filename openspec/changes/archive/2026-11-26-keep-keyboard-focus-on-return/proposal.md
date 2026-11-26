# Proposal

## Why

War im aktiven Training die Tastatur offen und kehrte der Nutzer nach dem Sperren über die Live Activity zurück, nahm der Trainingsscreen dem Feld den Fokus. Beim Ereignis `resumed` meldet iOS die Tastatur noch nicht wieder, der Screen hielt sie deshalb für geschlossen. iOS blendete sie danach trotzdem ein, aber ohne fokussiertes Feld: Weder die Leiste zum Ausblenden noch Wischen schlossen sie. Erst Tippen in ein Feld und wieder heraus half, etwa bevor der Timer gestellt werden konnte.

## What Changes

- Ob die Tastatur offen war, merkt sich der Trainingsscreen beim Verlassen der App, nicht beim Zurückkehren.
- War sie offen, behält das Feld den Fokus und die Leiste zum Ausblenden erscheint mit der Tastatur.
- War sie nicht offen, nimmt der Screen den Fokus wie bisher.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `training-session`: Anforderung „Zahleneingabe mit Navigationsleiste“ regelt den Fokus bei Rückkehr in die App.

## Impact

`_WorkoutScreenState.didChangeAppLifecycleState` in `workout_screen.dart` und Tests in `rest_timer_workout_test.dart`.
