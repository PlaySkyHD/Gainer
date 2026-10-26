# Tasks

## 1. Spec an den Code angleichen

- [x] 1.1 `body-tracking`: Anforderung „Getrennte freiwillige Health-Berechtigungen“ per MODIFIED anpassen und die Anforderung „Gemeinsamer Health-Dialog für Check-in-Typen“ per ADDED ergänzen. Prüfung: `NativeHealthKit.swift` `requestCheckInAuthorization()` fordert Gewicht, Schritte und Schlaf (lesen) sowie Gewicht und Schlaf (schreiben) in einer Anforderung. `check_in_health_coordinator.dart` ruft sie über `loadCheckInHealth` aus `body_screen.dart` beim Öffnen oder Umstellen des Check-in-Datums auf. Der Gewichtsimport ruft `requestBodyMassReadAuthorization` nur in `prepareWeightReview` auf, der Workout-Export `requestWorkoutWriteAuthorization` nur nach Bestätigung im Dialog „Workout nach Apple Health exportieren?“.
- [x] 1.2 Andere Specs auf denselben Widerspruch prüfen. Prüfung: `grep` nach „Berechtigung“, „Systemdialog“ und „Lesezugriff“ in `openspec/specs`. `overview` und `ios-app` widersprechen dem Code nicht.

## 2. Prüfung und Archivierung

- [x] 2.1 `openspec validate align-health-checkin-permissions --strict` ist grün.
- [x] 2.2 `openspec archive align-health-checkin-permissions -y` übernimmt das Delta in `openspec/specs/body-tracking/spec.md`.
- [x] 2.3 `openspec validate --specs --strict` ist grün, und unter `openspec/changes/` liegt nichts außerhalb von `archive/`.
- [x] 2.4 `git diff origin/main -- openspec/specs` zeigt nur die Anforderungen in `body-tracking`.
