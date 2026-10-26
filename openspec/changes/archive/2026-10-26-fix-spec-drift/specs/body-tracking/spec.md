## MODIFIED Requirements

### Requirement: Getrennte freiwillige Health-Berechtigungen

Die App MUST Gewicht-Lesezugriff und Workout-Schreibzugriff getrennt und nur nach Nutzeraktion anfordern. Ablehnung, Entzug oder nicht verfügbare Health-Daten MUST die Kernreise unverändert nutzbar lassen. Fehlende Leseergebnisse DÜRFEN nicht als sicher erkannte Berechtigungsverweigerung oder als Nullgewicht behandelt werden. Nutzung von HealthKit DARF keine automatische Serverübermittlung oder Ernährungsentscheidung auslösen. Ausnahme: Die Übersicht übernimmt Schritte aus Apple Health beim Laden automatisch in die Check-ins der letzten sieben Tage ohne heute (siehe `overview`, „Vergangene Tage nachziehen“). Diese Änderungen gelangen in den Gainer-Sync.

#### Scenario: Health-Zugriff nicht erteilt
- **GIVEN** der Nutzer erlaubt keinen Health-Zugriff oder es werden keine Werte geliefert
- **WHEN** er Körpertracking und Training verwendet
- **THEN** funktionieren manuelle Check-ins und Workouts weiter und die App erklärt den fehlenden Datenstand ohne erfundene Werte

#### Scenario: Schritte beim Laden der Übersicht übernehmen
- **GIVEN** der Check-in von gestern hat 1.200 Schritte und Apple Health meldet für gestern 11.800
- **WHEN** die Übersicht lädt
- **THEN** speichert der Check-in 11.800 Schritte, die Änderung wird synchronisiert, und Gewicht und Schlaf bleiben unverändert

### Requirement: Gewichtsimport mit Prüfung und Duplikatschutz

Die App MUST auf ausdrückliche Anfrage Gewichtsproben des gewählten Zeitraums mit Einheit, Messzeit und Quelle zur Auswahl anzeigen. Erst ausdrückliche Bestätigung DARF daraus eigene Check-ins mit atomarer Outbox machen. Dieselbe Health-Probe MUST pro Gainer-Konto wiederholbar ohne Duplikat behandelt werden; bestehende Check-ins DÜRFEN nicht still überschrieben werden. Vor Bestätigung MUST die App erklären, dass bestätigte Check-ins in den eigenen Gainer-Server-Sync gelangen.

#### Scenario: Messung prüfen und übernehmen
- **GIVEN** eine gültige Health-Gewichtsprobe und Konto A als aktives Schreibgerät
- **WHEN** A den Import prüft und bestätigt
- **THEN** wird ein eigener Check-in mit korrekt normalisierter Einheit/Datum und genau einer stabilen Mutation erzeugt

#### Scenario: Probe erneut importieren oder Konto wechseln
- **GIVEN** eine bereits importierte Probe von A oder ein bestehender Check-in am gleichen Tag
- **WHEN** ein erneuter Import oder ein Import unter Konto B angefragt wird
- **THEN** wird bei A kein Duplikat angelegt, ein fachlicher Tageskonflikt verlangt eine Entscheidung und B erhält keine Übernahme ohne eigene ausdrückliche Prüfung

#### Scenario: Review abbrechen
- **GIVEN** Health-Werte werden im Review angezeigt
- **WHEN** der Nutzer den Import abbricht
- **THEN** entstehen keine Gainer-Fachdaten und keine Servermutationen und temporäre Auswahlwerte werden verworfen
