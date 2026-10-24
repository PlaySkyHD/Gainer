# Proposal

## Why

Phase 1 (`add-cardio-heart-rate-tracking`) zeichnet Cardio-Einheiten mit Pulsgurt und Zonenalarm auf. Während der Einheit liegt das iPhone aber meist gesperrt auf dem Ergometer, und der Puls soll ohne Entsperren sichtbar sein. Außerdem gehören die Einheiten nach Apple Health. Und ein passender Zielbereich soll sich ohne Rechnen wählen lassen.

## What Changes

- **Live Activity für Cardio:** Sperrbildschirm und Dynamic Island zeigen Puls, Zonenstatus (im Bereich, zu hoch, zu niedrig, kein Signal), Zielbereich und Dauer. Swift aktualisiert sie direkt aus den Messwerten, also auch bei gesperrtem Display. Sie folgt der bestehenden Einstellung für Live Activities.
- **Export nach Apple Health:** In der Detailansicht speichert „In Apple Health sichern“ eine beendete Einheit als Indoor-Radtraining mit Pulsproben und, falls eingetragen, Distanz und kcal. Ein wiederholter Export erzeugt keine Dubletten.
- **Zonen-Empfehlung:** In den Cardio-Einstellungen lassen sich Maximalpuls (alternativ das Alter für eine Schätzung nach Tanaka: 208 − 0,7 × Alter) und optional Ruhepuls angeben. Daraus berechnet die App die Zonen 1–5. Beim Start und beim Ändern des Zielbereichs übernimmt ein Tipp auf „Zone 2“ usw. den Bereich.

### Non-Goals

- Keine automatische Messung von Maximal- oder Ruhepuls.
- Kein Import von Cardio-Einheiten aus Apple Health.
- Keine Apple Watch, kein Android.

## Capabilities

- **Neu:** `cardio-insights`.

## Impact

- **iOS:**
  - `GainerCardioActivityAttributes` (Shared) und Cardio-Activity-Ansicht im Widget-Extension-Target.
  - Steuerung der Live Activity im `NativeHeartRateMonitor`.
  - HealthKit-Export (`HKWorkoutActivityType.cycling`, Indoor-Metadaten, `heartRate`-Proben).
  - Berechtigungstexte.
- **Flutter:**
  - Zonenmodell und Einstellungen (lokal pro Konto, in den Trainingseinstellungen).
  - Zonen-Chips im Start-Sheet und beim Ändern des Bereichs.
  - Export-Aktion in der Detailansicht mit Ledger wie beim Workout-Export.
- **Backend:** keine Änderung.
- **Security:** Pulsproben gehen nur nach ausdrücklicher Aktion des Nutzers an HealthKit. Die Live Activity zeigt nur Puls, Zone und Dauer.
- **Breaking Changes:** keine.
