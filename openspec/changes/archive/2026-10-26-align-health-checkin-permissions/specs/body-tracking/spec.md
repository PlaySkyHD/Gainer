## RENAMED Requirements

- FROM: `### Requirement: Getrennte freiwillige Health-Berechtigungen`
- TO: `### Requirement: Freiwillige Health-Berechtigungen nach Nutzeraktion`

## MODIFIED Requirements

### Requirement: Freiwillige Health-Berechtigungen nach Nutzeraktion

Die App MUST Health-Berechtigungen nur nach einer Nutzeraktion anfordern. Gewichtsimport und Workout-Export MUST jeweils eigene Anforderungen sein. Ablehnung, Entzug oder nicht verfügbare Health-Daten MUST die Kernreise unverändert nutzbar lassen. Fehlende Leseergebnisse DÜRFEN nicht als sichere Verweigerung oder Nullgewicht gelten. HealthKit DARF keine automatische Serverübermittlung oder Ernährungsentscheidung auslösen. Ausnahme sind Schritte aus Apple Health, siehe Szenario.

#### Scenario: Health-Zugriff nicht erteilt
- **GIVEN** der Nutzer erlaubt keinen Health-Zugriff oder es werden keine Werte geliefert
- **WHEN** er Körpertracking und Training verwendet
- **THEN** funktionieren manuelle Check-ins und Workouts weiter und die App erklärt den fehlenden Datenstand ohne erfundene Werte

#### Scenario: Schritte beim Laden der Übersicht übernehmen
- **GIVEN** der Check-in von gestern hat 1.200 Schritte und Apple Health meldet für gestern 11.800
- **WHEN** die Übersicht lädt
- **THEN** speichert der Check-in 11.800 Schritte, die Änderung wird synchronisiert, und Gewicht und Schlaf bleiben unverändert

#### Scenario: Gewichtsimport fordert Gewicht-Lesezugriff gesondert an
- **GIVEN** der Nutzer hat den Gewichtsimport für einen Zeitraum noch nicht gestartet
- **WHEN** er den Import ausdrücklich startet
- **THEN** fordert die App den Gewicht-Lesezugriff getrennt an, bevor die Gewichtsproben geladen werden

#### Scenario: Workout-Export fordert Schreibzugriff erst nach Bestätigung an
- **GIVEN** ein abgeschlossenes Gainer-Workout und der Dialog „Workout nach Apple Health exportieren?“ ist offen
- **WHEN** der Nutzer „Abbrechen“ wählt
- **THEN** fordert die App keinen Workout-Schreibzugriff an und das Workout bleibt unverändert

## ADDED Requirements

### Requirement: Gemeinsamer Health-Dialog im Check-in-Formular

Für das Check-in-Formular MUST das Öffnen oder der Wechsel des Check-in-Datums genau eine Systemanforderung für Gewicht, Schritte und Schlaf (lesen) sowie Gewicht und Schlaf (schreiben) auslösen. Das Lesen der Übersicht MUST keine Berechtigungsanforderung auslösen. Das Ergebnis DARF NICHT als Zusage eines Lesezugriffs gewertet werden.

#### Scenario: Ein Systemdialog im Check-in-Formular
- **GIVEN** Apple Health ist auf dem Gerät verfügbar
- **WHEN** der Nutzer ein Check-in-Formular öffnet oder im Formular das Datum wechselt
- **THEN** stellt die App genau eine Anforderung für Gewicht, Schritte und Schlaf (lesen) sowie Gewicht und Schlaf (schreiben)

#### Scenario: Kein Berechtigungsdialog beim Lesen der Übersicht
- **GIVEN** der Nutzer hat noch kein Check-in-Formular geöffnet
- **WHEN** die Übersicht die Schritte für heute liest
- **THEN** erscheint kein Berechtigungsdialog

#### Scenario: Check-in-Formular ohne verfügbares Health
- **GIVEN** Apple Health ist auf dem Gerät nicht verfügbar
- **WHEN** der Nutzer ein Check-in-Formular öffnet
- **THEN** fordert die App keine Berechtigung an und der Check-in bleibt manuell nutzbar
