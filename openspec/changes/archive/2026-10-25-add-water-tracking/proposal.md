# Proposal

## Why

Einige Nutzer möchten neben dem Essen auch festhalten, wie viel Wasser sie am Tag trinken, und dabei ein Tagesziel im Blick haben. Bisher gibt es dafür keinen Ort in der App. Der Betreiber selbst braucht die Funktion nicht, deshalb darf sie die Ernährungsübersicht für alle anderen nicht voller machen (Issue #112).

## What Changes

- **Wassermenge pro Tag.** Für jeden lokalen Kalendertag speichert die App eine getrunkene Menge in ganzen Millilitern (0 bis 10.000 ml).
- **Eigene Sync-Ressource.** Die Tagesmenge ist eine neue synchronisierte Ressource `WaterIntakeDay` mit Version, Basisversion und Snapshot im Change-Feed. Sie lässt sich offline erfassen und erscheint damit automatisch im Datenexport.
- **Zwei Mutationen.** „Menge hinzufügen“ (`addWaterIntake`) für die Schnellknöpfe und „Tagesmenge setzen“ (`setWaterIntake`) für Korrektur und Rückgängig.
- **Wasser-Karte im Ernährungstag.** Unter der Tageskarte steht eine Karte mit „x / Ziel ml“ (z. B. „1.250 / 2.500 ml“), einem Fortschrittsbalken und drei Schnellknöpfen „+200 ml“, „+300 ml“ und „+500 ml“. Antippen der Menge öffnet ein Sheet, in dem der Nutzer die Tagesmenge korrigieren oder auf 0 ml zurücksetzen kann.
- **Standardmäßig ausgeblendet.** Ein neuer Eintrag „Einstellungen“ im Menü (…) der Ernährung öffnet die Ernährungs-Einstellungen mit dem Schalter „Wasser erfassen“ und dem Tagesziel (Standard 2.500 ml). Die Einstellungen gelten nur auf diesem Gerät und für dieses Konto, wie die Trainings- und Cardio-Einstellungen.

### Non-Goals

- Export nach Apple Health (Wasser) oder Import von dort.
- Einzelne Trinkvorgänge mit Uhrzeit oder Getränkeart; gespeichert wird nur die Tagessumme.
- Wasser aus Lebensmitteln oder Getränken im Ernährungstagebuch mitzählen.
- Wasser im Kalender, in den Durchschnitten, im Coach oder in Analytics.
- Das Tagesziel synchronisieren oder serverseitig speichern.
- Andere Einheiten als Milliliter.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `meal-tracking`: neue Anforderungen für die Wassermenge pro Tag, ihre Erfassung in der App, die Einstellungen und den Sync.

## Kernjourney

1. Die Nutzerin schaltet unter Ernährung › … › Einstellungen „Wasser erfassen“ ein und lässt das Ziel bei 2.500 ml.
2. Im Ernährungstag erscheint die Karte „Wasser · 0 / 2.500 ml“.
3. Sie tippt zweimal auf „+500 ml“ und einmal auf „+300 ml“. Die Karte zeigt „1.300 / 2.500 ml“, auch ohne Verbindung.
4. Ein Glas war doppelt gezählt: Sie tippt auf die Menge, gibt 800 ml ein und sichert.
5. Beim nächsten Sync landet der Stand auf dem Server und im Datenexport.

## Impact

- Backend: neue Entität, Tabelle `tracking.water_intake_days`, Migration `AddWaterTracking`, Handler, zwei Sync-Operationen, neuer `ResourceKind`.
- App: Sync-Codec, Konfliktanzeige, Repository, Einstellungen, Karte und Sheet im Tab „Essen“.
- Keine Änderung an bestehenden Endpunkten oder Ressourcen.
