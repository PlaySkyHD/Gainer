# Proposal

## Why

Der Coach beantwortet jede Frage ohne Gedächtnis. Dauerhafte Angaben wie ein Vorhaben („Halbmarathon im Mai“), Vorlieben, Unverträglichkeiten oder Verletzungen muss der Nutzer jedes Mal neu nennen. Gleichzeitig darf das Modell nichts eigenmächtig dauerhaft speichern: Eine Prompt-Injection, etwa über Produktnamen aus Open Food Facts, soll keine bleibenden Notizen erzeugen können (Issue #110).

## What Changes

- **Coach-Gedächtnis:** Neue nutzereigene Entität `CoachMemory` mit Kategorie (`goal`, `preference`, `intolerance`, `injury`, `other`) und Text (1–200 Zeichen). Höchstens 50 Einträge pro Nutzer, kein Ablaufdatum.
- **Verwaltung per REST:** `GET/POST/DELETE api/v1/coach/memories` und `PUT/DELETE api/v1/coach/memories/{id}`. Der Coach ist online-only, deshalb kein Sync-Ressourcentyp.
- **Vorschläge statt Schreibwerkzeuge:** Die strukturierte Coach-Antwort bekommt das Feld `memorySuggestions` (höchstens drei). Der Server prüft Kategorie und Länge und verwirft Duplikate. Gespeichert wird nur, wenn der Nutzer in der App „Merken“ tippt.
- **Kontext:** Bestätigte Einträge gehen als eigenes, klar markiertes Eingabe-Element mit Rolle `user` an das Modell, als Daten und nicht als Anweisungen, in der Gesamtlänge begrenzt.
- **App:** Vorschläge unter der Antwort mit „Merken“ und „Verwerfen“; neuer Screen „Gedächtnis“ mit Liste nach Kategorie, Bearbeiten, Hinzufügen, Wischen zum Löschen und „Alles vergessen“. Ohne Verbindung sind Änderungen gesperrt und der Grund steht da.

### Non-Goals

- Keine schreibenden Coach-Werkzeuge und kein automatisches Speichern.
- Kein Ablaufdatum, keine Synchronisierung über die Outbox, kein Gesprächsverlauf.
- Der medizinische Vorfilter für Fragen bleibt unverändert.

## Capabilities

- **Geändert:** `ai-coach` (ADDED „Coach-Gedächtnis mit Bestätigung“ und „Verwaltung des Coach-Gedächtnisses“, MODIFIED „Datenminimierung und deaktivierte Anbieter-Speicherung“).

## Impact

- Backend: Core (`CoachMemory`, `ICoachMemoryStore`), Infrastructure (`CoachMemoryStore`, `AppDbContext`, Migration `AddCoachMemory`, `CoachService`), Api (`CoachMemoriesController`, `CoachController`), Contracts, OpenAPI.
- App: API-Client und Modelle, `CoachMemoryRepository`, Coach-Screen und neuer Gedächtnis-Screen.
