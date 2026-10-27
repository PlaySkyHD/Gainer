# Tasks

## 1. Kulanzfrist verlängern

- [x] 1.1 `ReuseGracePeriod` auf 6 Stunden setzen. Prüfung: `DeviceSessionService.cs`.
- [x] 1.2 Integrationstests für Retry nach 30 Minuten und für den älteren Vorgänger. Prüfung: `AuthenticationApiTests` grün.
- [x] 1.3 Spec `account-access` anpassen. Prüfung: `openspec validate --specs --strict` grün.
