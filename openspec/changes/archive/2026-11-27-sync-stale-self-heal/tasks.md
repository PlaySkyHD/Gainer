# Tasks

## 1. Server

- [x] 1.1 `stale_base_version` nennt `serverVersion` und `serverDeleted` aus dem Änderungsfeed. Prüfung: `SyncBaseVersionAndReplayTests`, `SyncMutationsControllerTests` grün.

## 2. App

- [x] 2.1 Automatisches Aufsetzen auf eine neuere Serverversion, je Ressource und Version einmal. Prüfung: `sync_reliability_test.dart` grün, ohne den Fix rot.
- [x] 2.2 Konflikthinweis über allen Tabs mit Anzahl und „Ansehen“, ohne Überlauf bei Textgröße 1,0, 1,3 und 2,0 auf 320 pt. Prüfung: `sync_status_banner_test.dart`, `sync_status_test.dart` grün.

## 3. Spec

- [x] 3.1 `openspec validate --specs --strict` grün.
