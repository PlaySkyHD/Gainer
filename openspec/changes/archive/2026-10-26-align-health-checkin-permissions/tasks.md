# Tasks

## 1. Spec an den Code angleichen

- [x] 1.1 `body-tracking`: Anforderung „Getrennte freiwillige Health-Berechtigungen“ per RENAMED umbenennen und per MODIFIED anpassen. Prüfung im Code: `NativeHealthKit.swift` `requestCheckInAuthorization()` fordert alle Check-in-Typen in einer Anforderung. Aufrufer ist `CheckInHealthCoordinator.load()` über `loadCheckInHealth` in `body_screen.dart`, beim Öffnen und beim Datumswechsel. Der Gewichtsimport ruft `requestBodyMassReadAuthorization` nur in `prepareWeightReview` auf, der Workout-Export `requestWorkoutWriteAuthorization` nur nach Bestätigung.
- [x] 1.2 `body-tracking`: Anforderung „Gemeinsamer Health-Dialog im Check-in-Formular“ per ADDED ergänzen.
- [x] 1.3 Andere Specs prüfen. `overview` und `ios-app` widersprechen dem Code nicht.

## 2. Prüfung und Archivierung

- [x] 2.1 `openspec validate align-health-checkin-permissions --strict` ist grün.
- [x] 2.2 `openspec archive align-health-checkin-permissions -y` übernimmt das Delta in `openspec/specs/body-tracking/spec.md`.
- [x] 2.3 `openspec validate --specs --strict` ist grün.
- [x] 2.4 `git diff origin/main -- openspec/specs` zeigt nur die Anforderungen in `body-tracking`.
