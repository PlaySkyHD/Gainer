# Proposal

## Why

Schritte kommen nur beim Check-in aus Apple Health und werden dann im Check-in gespeichert. Wer morgens eincheckt, sieht den ganzen Tag den Morgenwert, und auch im Verlauf, im Kalender und beim Coach bleibt dieser zu niedrige Wert stehen.

## What Changes

- **Heute live:** Die Übersicht liest die Schritte von heute direkt aus Apple Health, jedes Mal wenn sie sichtbar wird, die App zurückkommt oder der Nutzer herunterzieht. Der Wert steht in der Check-in-Karte, auch wenn es heute noch keinen Check-in gibt.
- **Vergangene Tage nachziehen:** Beim selben Anlass holt die App für Check-ins der letzten 7 Tage (ohne heute) die fertige Tagessumme aus Apple Health. Weicht sie vom gespeicherten Wert ab, wird der Check-in aktualisiert und synchronisiert. So stimmen Verlauf, Kalender und Coach ab dem nächsten Tag.
- Dabei erscheint kein Berechtigungsdialog: Gelesen wird nur, wenn der Check-in den Zugriff schon angefragt hat. Ohne Zugriff oder ohne Daten bleibt alles, wie es ist.

### Non-Goals

- Kein Hintergrund-Abgleich, wenn die App geschlossen ist (iOS verspricht keinen Hintergrund-Sync).
- Der heutige Check-in wird nicht laufend überschrieben; heute zählt der Live-Wert, gespeichert wird er am Folgetag.
- Kein Anlegen von Check-ins nur für Schritte; ein Check-in braucht weiter ein Gewicht.

## Capabilities

- **Neu:** `live-steps`.

## Impact

- **App:**
  - `CheckInHealthCoordinator.readSteps` liest einen Tag ohne Berechtigungsdialog.
  - `BodyRepository.updateSteps` ändert nur die Schritte eines vorhandenen Check-ins.
  - Neuer `HealthStepsSync` mit `today()` und `syncRecent()`.
  - `CalendarScreen` und `CalendarDayView` zeigen die Live-Schritte.
- **Backend, API:** keine Änderung. Geänderte Check-ins laufen über den bestehenden Sync (`update`).
- **Security:** keine neuen Berechtigungen; Health-Daten verlassen das Gerät nur als Schrittzahl im eigenen Check-in wie bisher.
- **Breaking Changes:** keine.
