# Proposal

## Why

Ein nachträgliches Code Review des Coach-Gedächtnisses (#117) fand zehn Lücken (Issue #122). Für die Specs relevant sind drei: Der Datenexport (#109) enthält die Gedächtnis-Einträge nicht, gleichzeitige Änderungen eines Eintrags überschreiben sich still, und derselbe Text mit anderer Kategorie wird beim Anlegen ignoriert, obwohl die App „Gemerkt“ zeigt.

## What Changes

- **Export:** `GET /api/v1/account/export` enthält neben `resources` den Abschnitt `coachMemories` mit allen Einträgen des Nutzers. Das Feld ist neu und optional, `schemaVersion` bleibt 1.
- **Versionsprüfung:** `PUT /api/v1/coach/memories/{id}` nimmt `baseVersion` an. Weicht die gespeicherte Version ab, antwortet der Server mit 409 `memory_conflict`; die App zeigt einen Hinweis und lädt neu. Ohne `baseVersion` (ältere App-Builds) bleibt die Änderung ungeprüft.
- **Gleicher Text, andere Kategorie:** Das Anlegen übernimmt die neue Kategorie in den vorhandenen Eintrag, erhöht dessen Version und antwortet mit 200. Der Eintrag behält seinen Platz in der Liste.
- **Ohne Spec-Änderung:** App-seitige Robustheit (unbekannte Kategorie, gesperrtes „Merken“, Löschen mit 404, Editor bleibt bei Fehlern offen, einheitliches Längenmaß in UTF-16-Einheiten, eigenes ViewModel des Screens) und Notizen ohne `\uXXXX` im Prompt mit Budget an der gesendeten Länge.

### Non-Goals

- Keine Migration, `Version` existiert bereits.
- Kein Import der Gedächtnis-Einträge.

## Capabilities

- **Geändert:** `account-access` (MODIFIED „Export der eigenen Daten“), `ai-coach` (MODIFIED „Verwaltung des Coach-Gedächtnisses“).

## Impact

- Backend: `CoachMemoryStore`, `CoachMemoriesController`, `CoachService`, `AccountDataExportQuery`, `AccountExportController`, Contracts, OpenAPI.
- App: Modelle, `CoachMemoryRepository`, API-Client, Coach-Screen und Gedächtnis-Screen.
