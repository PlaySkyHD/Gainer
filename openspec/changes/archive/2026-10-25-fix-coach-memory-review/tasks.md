# Tasks

## 1. Backend

- [x] 1.1 Anlegen mit gleichem Text und anderer Kategorie aktualisiert den vorhandenen Eintrag; Integrationstest.
- [x] 1.2 `baseVersion` beim Ändern, 409 `memory_conflict`; Integrationstest mit zwei gleichzeitigen Änderungen.
- [x] 1.3 Export mit `coachMemories`; Test in `AccountDataExportTests` mit zwei Nutzern.
- [x] 1.4 Notizen im Prompt ohne `\uXXXX`, Budget an der gesendeten Länge; Test in `CoachServiceTests`.

## 2. App

- [x] 2.1 Unbekannte Kategorie als „Sonstiges“, Löschen mit 404 als Erfolg, `baseVersion` beim Ändern; Tests.
- [x] 2.2 „Merken“ offline und bei vollem Gedächtnis gesperrt, Grund sichtbar; Widget-Tests.
- [x] 2.3 Editor bleibt bei Fehlern offen, Konflikt lädt neu, ein Längenmaß (UTF-16); Widget-Tests.
- [x] 2.4 `CoachMemoryScreen` besitzt sein ViewModel.
