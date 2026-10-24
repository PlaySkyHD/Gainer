# Design

## Decisions

### D1 – Heutige Kalorien lokal

`ProgressViewModel` erhält optional das `NutritionRepository` und liest `read(lokalesDatum).day.totals`. So funktioniert die Karte offline und zeigt neue Einträge sofort. Das Datum ist der lokale Kalendertag (nicht UTC). Schlägt das Lesen fehl, bleibt der zuletzt gezeigte Wert stehen; ohne je gelesenen Wert zeigt die Karte „Noch nichts erfasst“.

### D2 – Neu lesen

Die Tabs bleiben nach dem ersten Anzeigen erhalten, daher lädt nur `initState` allein nicht neu. Die Shell reicht `ProgressScreen` den aktiven Tab durch; beim Wechsel zurück auf „Heute“ ruft der Screen `refreshToday()` auf. `load()` (Start, Herunterziehen) liest die lokalen Werte ebenfalls neu.

### D3 – Alter des Gewichts

`WeightAge.fromDate(datum, heute)` zählt Kalendertage zwischen dem Datum des letzten Eintrags und dem lokalen heutigen Tag (über UTC-Mitternacht, damit die Sommerzeit nichts verschiebt). Zukünftige oder ungültige Daten zählen als „Heute“. Farben: `secondaryText`, `warning`, `destructive` aus `GainerColors`. Das Label hat eine Semantik „Letztes Gewicht: …“.
