# Proposal

## Why

Der Nutzer möchte über ChatGPT alles abfragen können, was er in der App sieht, wie mit einem lesenden CLI. Bisher liefert der MCP-Server nur Überblick, Trainingsliste, Training, Übungssuche und Übungsentwicklung. Eine Bestandsaufnahme zeigt: Viele Ansichten stützen sich auf Daten, für die der Server schon Abfragen hat, die das MCP aber nicht nutzt. Diese Änderung ist die erste von vier Stufen und deckt genau diesen Teil ab.

## What Changes

- `get_overview` liefert zusätzlich die tägliche Gewichtsreihe, den 7-Tage-Durchschnitt und die Trainings der letzten 7 Tage (Gewichtskarte und Trainingsübersicht der Übersicht).
- Neue lesende Tools:
  - `get_body_goals`: aktives Ziel und Verlauf
  - `list_check_ins`: Gewicht, Schritte, Schlaf, Ruhepuls, HRV je Tag, höchstens 366 Tage
  - `get_nutrition_days`: Einträge, Summen, Tagesart und geltendes Ziel je Tag, höchstens 31 Tage
  - `get_nutrition_targets`: Zielplan mit allen Versionen
  - `list_saved_meals`: gespeicherte Gerichte
  - `list_coach_notes`: Coach-Gedächtnis
  - `get_strava_status`: Strava-Verbindung
- `IBodyTrackingQueries.GetCheckInsBetweenAsync` liefert Check-ins eines Datumsbereichs.
- Aufzählungswerte erscheinen in Tool-Antworten als Namen statt als Zahlen.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `ai-connector`: Anforderung „Lesende Tools“ nennt die neuen Tools und die Bereichsgrenzen.

## Impact

`Gainer.Api/Mcp` (neue Tool-Klassen `GainerBodyTools`, `GainerNutritionTools`, `GainerAccountTools`, `McpDates`), `GainerConnectorExtensions`, `IBodyTrackingQueries` und `BodyTrackingQueries`. Keine Migration, kein Sync.
