# Tasks

## 1. Backend

- [x] 1.1 `CoachMemory`, Kategorien, Grenzen und `ICoachMemoryStore` in Core; Konfiguration in `AppDbContext`, Migration `AddCoachMemory` (D1).
- [x] 1.2 `CoachMemoryStore` mit Lock, Grenze und Duplikaterkennung (D2); Integrationstests gegen Postgres mit zwei Nutzern.
- [x] 1.3 `CoachMemoriesController` mit ProblemDetails-Codes (D3); Tests für 404 bei fremden und unbekannten IDs.
- [x] 1.4 `CoachService`: Einträge als Daten-Element, zitierbare Gedächtnis-IDs, `memorySuggestions` im Schema und serverseitige Prüfung (D4, D5); Tests in `CoachServiceTests` und `CoachToolSchemaTests`.
- [x] 1.5 `CoachResponse` um `MemorySuggestions` erweitern, OpenAPI neu erzeugen.

## 2. App

- [x] 2.1 API-Client, Modelle und `CoachMemoryRepository` (D6); Tests.
- [x] 2.2 Vorschläge im Coach-Screen mit „Merken“ und „Verwerfen“; Widget-Tests.
- [x] 2.3 Screen „Gedächtnis“ mit Liste, Bearbeiten, Hinzufügen, Löschen, „Alles vergessen“ und Offline-Sperre; Widget- und Golden-Tests.
