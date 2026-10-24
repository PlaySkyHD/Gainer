# live-steps

## ADDED Requirements

### Requirement: Schritte von heute live

Die Übersicht SHALL für heute die Schrittzahl aus Apple Health zeigen und sie neu lesen, wenn die Übersicht sichtbar wird, die App zurückkommt oder der Nutzer herunterzieht. Der Live-Wert SHALL den gespeicherten Wert des heutigen Check-ins ersetzen. Gibt es heute keinen Check-in, SHALL die Check-in-Karte nur die Schritte zeigen. Das Lesen MUST NOT einen Berechtigungsdialog öffnen.

#### Scenario: Morgens eingecheckt, mittags geöffnet
- **GIVEN** der heutige Check-in hat um 7 Uhr 1.200 Schritte gespeichert und Apple Health meldet jetzt 8.450
- **WHEN** der Nutzer die Übersicht öffnet
- **THEN** zeigt die Check-in-Karte „Schritte 8.450“

#### Scenario: Noch kein Check-in heute
- **GIVEN** es gibt heute keinen Check-in und Apple Health meldet 3.100 Schritte
- **WHEN** die Übersicht lädt
- **THEN** zeigt die Check-in-Karte nur „Schritte 3.100“

#### Scenario: Kein Zugriff
- **GIVEN** Apple Health liefert keine Schritte
- **WHEN** die Übersicht lädt
- **THEN** bleibt der gespeicherte Wert stehen, und es erscheint kein Dialog

### Requirement: Vergangene Tage nachziehen

Beim selben Anlass SHALL die App für Check-ins der letzten 7 Tage ohne heute die Tagessumme aus Apple Health lesen. Ist sie größer als 0 und weicht sie vom gespeicherten Wert ab, SHALL sie nur die Schritte des Check-ins aktualisieren und synchronisieren; alle anderen Werte MUST unverändert bleiben. Tage ohne Check-in MUST NOT angelegt werden.

#### Scenario: Gestern nachgezogen
- **GIVEN** der Check-in von gestern hat 1.200 Schritte und Apple Health meldet für gestern 11.800
- **WHEN** die Übersicht heute lädt
- **THEN** speichert der Check-in von gestern 11.800 Schritte mit unverändertem Gewicht und Schlaf, und eine Sync-Änderung ist vorgemerkt

#### Scenario: Unverändert
- **GIVEN** der gespeicherte Wert entspricht Apple Health
- **WHEN** die Übersicht lädt
- **THEN** entsteht keine Sync-Änderung
