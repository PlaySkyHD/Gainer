# Proposal

## Why

Auf einem einzigen Gerät erschienen Sync-Konflikte für Ernährungstage mit dem Hinweis „Auf dem Server gibt es eine neuere Version“. Es gab keine neuere Version. Der Server ersetzt beim Speichern alle Einträge eines Tags und nutzt dabei dieselben Eintrags-IDs. Verschiebt sich dabei eine Position, etwa weil der erste Eintrag einer Mahlzeit gelöscht wurde, verletzt die Datenbank die Eindeutigkeit von Mahlzeit und Position. Der Server meldete das als veraltete Basisversion. Die Selbstheilung der App greift nicht, weil der lokale Stand genau der abgelehnte ist. Gerichte haben denselben Fehler bei ihren Komponenten.

## What Changes

- Ernährungstag und Gericht speichern das Entfernen der alten Einträge bzw. Komponenten zuerst und legen die neuen erst danach an, in einer gemeinsamen Transaktion. Trainingspläne, Trainings und der Trainingskalender machen das bereits so.
- Integrationstests für Löschen des ersten Eintrags, Einfügen oben, Tauschen und Verschieben in eine andere Mahlzeit sowie für Komponenten eines Gerichts.

### Non-Goals

- Keine Änderung an der App. Bestehende Konflikte löst der Nutzer nach dem Deploy mit „Lokalen Stand behalten“.
- Kein neuer Fehlercode. Doppelte Positionen lehnt die Validierung schon vorher ab; nach dem Fix bleibt als Datenbankkonflikt nur ein echter Fall (gleiches Datum unter anderer ID).

## Capabilities

- **Geändert:** `meal-tracking`, `reusable-meals`.

## Impact

- Backend: `NutritionDayMutationHandler`, `ReusableMealMutationHandler`. Kein Schema, keine Migration, keine Vertragsänderung.
