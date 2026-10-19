# Proposal

## Why

Auf der Übersicht „Heute“ zeigte die Ernährungskarte „333 kcal pro Tag“. Das war der Serverdurchschnitt je erfasstem Tag der letzten 30 Tage; war nur gestern etwas erfasst, wirkte der heutige Tag mit 0 kcal wie 333 kcal. Die Gewichtskarte zeigt den letzten Wert ohne Hinweis, wie alt er ist.

## What Changes

- **Ernährung:** Die große Zahl sind die Kalorien von heute aus den lokalen Ernährungsdaten („1.280 kcal heute“), darunter das heutige Protein, sofern bekannt. Ohne Einträge steht „0 kcal heute“. Der 30-Tage-Durchschnitt erscheint auf der Karte nicht mehr. Die Werte werden neu gelesen, sobald der Tab wieder sichtbar wird, und beim Aktualisieren.
- **Gewicht:** Unter dem Wert steht das Alter des letzten Eintrags: „Heute“, „Gestern“, ab 2 Tagen „vor 3 Tagen“ in Warnfarbe, ab 7 Tagen in Fehlerfarbe.
- Die Trainingskarte bleibt unverändert.

### Non-Goals

- Kein Durchschnitt an anderer Stelle in dieser Änderung.
- Keine Änderung am Server oder an der Synchronisierung.

## Capabilities

- **Neu:** `today-overview`.

## Impact

- Flutter: `progress_screen.dart`, `progress_view_model.dart`, `weight_age.dart`, `mobile_shell.dart`, `mobile_auth_controller.dart`.
