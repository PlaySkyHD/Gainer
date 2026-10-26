## MODIFIED Requirements

### Requirement: Getrennte freiwillige Health-Berechtigungen

Die App MUST Health-Berechtigungen nur nach einer Nutzeraktion anfordern. Gewichtsimport (Gewicht-Lesezugriff) und Workout-Export (Workout-Schreibzugriff) MUST jeweils eigene Anforderungen sein. Ablehnung, Entzug oder nicht verfügbare Health-Daten MUST die Kernreise unverändert nutzbar lassen. Fehlende Leseergebnisse DÜRFEN nicht als sicher erkannte Berechtigungsverweigerung oder als Nullgewicht behandelt werden. Nutzung von HealthKit DARF keine automatische Serverübermittlung oder Ernährungsentscheidung auslösen. Ausnahme sind Schritte aus Apple Health, siehe Szenario.

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

### Requirement: Gemeinsamer Health-Dialog für Check-in-Typen

Die App MUST alle Check-in-Typen in einer einzigen Systemanforderung abfragen: Gewicht, Schritte und Schlaf lesen sowie Gewicht und Schlaf schreiben. Die Anforderung MUST nur beim Öffnen eines Check-ins oder beim Wechsel des Check-in-Datums erfolgen, nie beim Lesen der Übersicht. Das Ergebnis DARF NICHT als Zusage eines Lesezugriffs gewertet werden.

#### Scenario: Ein Systemdialog für alle Check-in-Typen
- **GIVEN** Apple Health ist auf dem Gerät verfügbar
- **WHEN** der Nutzer einen Check-in öffnet oder im Check-in das Datum wechselt
- **THEN** stellt die App genau eine Anforderung für Gewicht, Schritte und Schlaf (lesen) sowie Gewicht und Schlaf (schreiben)

#### Scenario: Kein Berechtigungsdialog beim Lesen der Übersicht
- **GIVEN** der Nutzer hat noch keinen Check-in geöffnet
- **WHEN** die Übersicht die Schritte für heute liest
- **THEN** erscheint kein Berechtigungsdialog

#### Scenario: Check-in ohne verfügbares Health
- **GIVEN** Apple Health ist auf dem Gerät nicht verfügbar
- **WHEN** der Nutzer einen Check-in öffnet
- **THEN** fordert die App keine Berechtigung an und der Check-in bleibt manuell nutzbar
