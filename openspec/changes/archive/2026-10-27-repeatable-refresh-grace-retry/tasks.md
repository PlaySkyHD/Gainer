# Tasks

## 1. Wiederholbare Grace-Retries

- [x] 1.1 `IsGraceRetry` nicht mehr an einen früheren Retry binden. Prüfung: `DeviceSessionService.cs`.
- [x] 1.2 Integrationstests für zwei verlorene Antworten, verworfenen Token, benutzten Nachfolger und Fristende. Prüfung: `AuthenticationApiTests` grün.
- [x] 1.3 Spec `account-access` anpassen. Prüfung: `openspec validate --specs --strict` grün.
