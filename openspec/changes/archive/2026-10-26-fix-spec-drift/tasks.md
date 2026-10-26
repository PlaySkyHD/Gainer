# Tasks

## 1. Specs an den Code angleichen

- [x] 1.1 `offline-sync`: „Protokoll v3“ durch „aktuelle Protokollversion“ ersetzen. Prüfung: `SyncContracts.cs` und `sync_protocol.dart` nennen 4.
- [x] 1.2 `meal-tracking`: Kilokalorien dürfen 0 sein. Prüfung: Eintragsprüfung in `nutrition.dart` lässt 0 zu, und „Selbst gesalzen“ hat 0 kcal.
- [x] 1.3 `body-tracking`: Ausnahme für die Schritteübernahme aus Apple Health in die HealthKit-Anforderung. Prüfung: `health_steps_sync.dart` übernimmt beim Laden automatisch.
- [x] 1.4 `body-tracking`: „Writer“ durch „Schreibgerät“ ersetzen.
- [x] 1.5 `ios-app`: Node.js und npm nur im Workflow „OpenSpec“. Prüfung: nur `.github/workflows/openspec.yml` nutzt `setup-node` und `npm`.
- [x] 1.6 `training-session`: Button „Ja, Vorwerte verwenden“ in Anforderung und Szenarien. Prüfung: `workout_screen.dart` zeigt diesen Text.
- [x] 1.7 `training-session`: Vorwertquellen mit den Bezeichnungen des Sheets; „Trainingsplan“ nur mit Plan. Prüfung: `repeat_workout_sheet.dart`.
- [x] 1.8 `strava-export`: höchstens sechs Versuche. Prüfung: `MaximumAttempts = 6` in `StravaExportProcessor.cs`.
- [x] 1.9 `account-access`: GIVEN in allen Szenarien der sechs Anforderungen ergänzen (7 Szenarien, darunter „Großer Body an einem anderen Endpunkt“). Prüfung: `openspec validate --specs --strict`.
- [x] 1.10 `reusable-meals` und `training-statistics`: englische Begriffe übersetzen. Überschriften bleiben unverändert, siehe proposal.md.

## 2. Prüfung und Archivierung

- [x] 2.1 `openspec validate fix-spec-drift --strict` ist grün.
- [x] 2.2 `openspec archive fix-spec-drift -y` übernimmt die Deltas in `openspec/specs/`.
- [x] 2.3 `openspec validate --specs --strict` ist grün, und unter `openspec/changes/` liegt nichts außerhalb von `archive/`.
- [x] 2.4 `git diff origin/main -- openspec/specs` zeigt nur die oben genannten Stellen.
