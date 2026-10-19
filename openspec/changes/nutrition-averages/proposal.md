# Proposal

## Why

Die Übersicht „Heute“ zeigte den 30-Tage-Schnitt „kcal pro Tag“ vom Server. Der Wert war dort fehl am Platz und verwirrte, weil unklar blieb, was gezählt wird. Der Durchschnitt gehört in den Tab „Essen“, wo die Daten entstehen, und soll offline aus den lokalen Tagen berechnet werden.

## What Changes

- Neue Zeile unter der Tageskarte im Tab „Essen“: „Durchschnitt – Ø 7 Tage 2.160 kcal · Protein 140 g“ mit Pfeil. Ohne Einträge zeigt sie „Noch keine Einträge“ und ist nicht antippbar.
- Sheet „Durchschnitt“ mit Umschalter 7 Tage / 30 Tage: Ø kcal pro erfasstem Tag, Erfassungsquote, Ø Protein/Kohlenhydrate/Fett, Zielvergleich (wenn ein Zielplan gilt) und Balkendiagramm je Tag mit Ziellinie.
- Reine Domänenberechnung `NutritionAverages` aus lokalen Ernährungstagen.

### Non-Goals

- Keine Server- oder Backend-Änderung, keine Änderung an „Heute“ (eigener Change).
- Kein Eintrag im Toolbar-Menü: Die Zeile ist ohne Umweg sichtbar, das Menü bleibt für Verwaltung („Gerichte und Ziele“).

## Capabilities

- **Neu:** `nutrition-averages`.

## Impact

- Flutter: `nutrition_averages.dart`, `nutrition_repository.dart`, `nutrition_averages_view.dart`, `nutrition_screen_cupertino.dart`, Tests und Goldens.
