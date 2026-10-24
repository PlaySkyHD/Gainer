# Tasks

## 1. Daten

- [x] 1.1 `CheckInHealthCoordinator.readSteps(localDate)` ohne Berechtigungsanfrage; Tests mit `FakeHealthPlatform`.
- [x] 1.2 `BodyRepository.updateSteps(localDate, steps)`: nur vorhandene Check-ins, nur bei Abweichung; Tests inkl. Outbox.
- [x] 1.3 `HealthStepsSync.today()` und `syncRecent(days: 7)`; Tests.

## 2. Übersicht

- [x] 2.1 `CalendarScreen` liest beim Laden, Sichtbarwerden, Zurückkehren und Herunterziehen; lädt neu, wenn Tage nachgezogen wurden.
- [x] 2.2 `CalendarDayView`: Live-Schritte für heute, Karte auch ohne Check-in. Widget-Tests.

## 3. Abschluss

- [x] 3.1 `openspec validate add-live-steps --strict`, lokal Analyse, Format und Flutter-Tests grün.
- [ ] 3.2 CI grün, TestFlight; auf dem iPhone mittags prüfen, ob die Schritte stimmen.
