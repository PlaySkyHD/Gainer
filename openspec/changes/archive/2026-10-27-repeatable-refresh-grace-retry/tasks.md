# Tasks

## 1. Wiederholbare Grace-Retries

- [x] 1.1 `IsGraceRetry` nicht mehr an einen früheren Retry binden. Prüfung: `DeviceSessionService.cs`.
- [x] 1.2 Alle verworfenen Tokens je Session in `device_session_discarded_tokens` speichern, Obergrenze zehn Retries je Rotation, Migration der bisherigen Spalte. Prüfung: Migration und `DeviceSessionService.cs`.
- [x] 1.3 Integrationstests für zwei verlorene Antworten, verworfenen Token, benutzten Nachfolger und Fristende. Prüfung: `AuthenticationApiTests` grün.
- [x] 1.4 Spec `account-access` anpassen. Prüfung: `openspec validate --specs --strict` grün.
