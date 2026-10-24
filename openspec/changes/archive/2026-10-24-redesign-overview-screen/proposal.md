# Proposal

## Why

Der erste Tab heißt „Kalender“ und zeigt oben den Monatskalender. Meistens interessiert aber der heutige Tag: Ernährung, Gewicht, Training und Check-in stehen erst unter dem Kalender. Die Makros der Ernährungskarte sind farblos und schwer zu unterscheiden, und Ballaststoffe und Salz hängen links unter drei Spalten.

## What Changes

- Der Tab und die Seite heißen **„Übersicht“**.
- Oben steht der gewählte Tag mit allen Werten:
  1. Plan oder Training des Tages
  2. Ernährung
  3. Gewicht
  4. Trainingsübersicht
  5. Check-in
- Der **Monatskalender** steht als letzte Karte unten. Wählst du dort einen Tag, scrollt die Seite nach oben zu dessen Werten.
- Oben links steht die **Tages-Pille „‹ Heute ›“** wie in der Ernährung: Die Pfeile wechseln einen Tag zurück oder vor, ein Tipp auf den Text scrollt zum Kalender. Ist ein anderer Tag als heute gewählt, führt „Zu heute“ rechts neben der Datumsüberschrift zurück.
- Die Tages-Pille wird ein gemeinsamer Baustein (`GainerDayNavigator`), den Übersicht und Ernährung nutzen.
- **Farben für Makros:** Kohlenhydrate grün, Eiweiß blau, Fett magenta. Sie gelten mit Punkt und Balken auf der Ernährungskarte der Übersicht und auf der Tageskarte im Tab „Essen“. Ballaststoffe und Salz behalten neutrale Balken und stehen zentriert in einer eigenen Zeile.

### Non-Goals

- Keine Wochenleiste oben; der Tagwechsel bleibt bei Pfeilen und dem Kalender unten.
- Keine neuen Daten oder Kennzahlen.
- Orange bleibt der Warnung vorbehalten (über dem Ziel) und wird keine Makrofarbe.

## Capabilities

- **Neu:** `overview-screen`.

## Impact

- **App:**
  - `MobileArea.calendar` mit Bezeichnung „Übersicht“
  - `calendar_screen.dart`, `calendar_day_view.dart`, `calendar_nutrition_overview.dart`
  - Tageskarte in `nutrition_screen_cupertino.dart`
  - neue Rollen `protein`, `carbohydrate`, `fat` in `GainerColors`
  - neuer Baustein `GainerDayNavigator`
  - `GainerProgressBar.color`
  - Tests, Goldens; `integration_test/ui_design_flow.dart` und `scripts/Verify-Mobile.ps1`, falls sie „Kalender“ ansprechen
- **Backend, API, Sync:** keine Änderung.
- **Security:** keine Auswirkung.
- **Breaking Changes:** keine.
