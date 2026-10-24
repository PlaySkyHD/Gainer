# Proposal

## Why

Für eigene Übungen, die nicht im Katalog stehen, muss der Nutzer Haupt- und Hilfsmuskeln selbst kennen. Bei Varianten wie „Rudern“ hängt das zudem von Gerät und Griff ab.

## What Changes

- **„Mit KI ermitteln“** im Abschnitt „Muskeln“ des Übungseditors öffnet einen Dialog.
- Die KI bekommt Name, Typ und Notiz der Übung. Ist die Variante unklar, stellt sie eine Rückfrage mit Antwort-Optionen und Freitext, höchstens zweimal.
- Danach zeigt sie einen Vorschlag auf der Körperkarte mit kurzer Begründung. „Übernehmen“ setzt die Muskeln im Editor; gespeichert wird wie bisher.
- Backend-Endpunkt `POST /api/v1/exercises/muscle-suggestions` mit festem Antwortschema und Tageslimit pro Nutzer.

### Non-Goals

- Kein automatisches Speichern und keine Massenauswertung aller Übungen.
- Kein Dialogverlauf auf dem Server.

## Capabilities

- **Neu:** `ai-muscle-suggestions`.

## Impact

- Backend: neuer Controller, `OpenAiMuscleSuggester`, Kontingent `MuscleSuggestion`, gemeinsames `DailyRequestQuota` (auch für die Mahlzeiten-Schätzung), OpenAPI.
- Flutter: `MuscleSuggestionService`, API-Aufruf, Sheet „Muskeln mit KI“, Button im Übungseditor.
