## Purpose

Diese Capability verbindet Gainer freiwillig und datensparsam mit Apple Health, ohne ungeprüfte Gesundheitswerte in die Tracking- oder Sync-Daten zu übernehmen.

## ADDED Requirements

### Requirement: Getrennte freiwillige Health-Berechtigungen

Die App MUST Gewicht-Lesezugriff und Workout-Schreibzugriff getrennt und nur nach Nutzeraktion anfordern. Ablehnung, Entzug oder nicht verfügbare Health-Daten MUST die Kernreise unverändert nutzbar lassen. Fehlende Leseergebnisse DÜRFEN nicht als sicher erkannte Berechtigungsverweigerung oder als Nullgewicht behandelt werden. Nutzung von HealthKit DARF keine automatische Serverübermittlung oder Ernährungsentscheidung auslösen.

#### Scenario: Health-Zugriff nicht erteilt
- **GIVEN** der Nutzer erlaubt keinen Health-Zugriff oder es werden keine Werte geliefert
- **WHEN** er Körpertracking und Training verwendet
- **THEN** funktionieren manuelle Check-ins und Workouts weiter und die App erklärt den fehlenden Datenstand ohne erfundene Werte

### Requirement: Gewichtsimport mit Prüfung und Duplikatschutz

Die App MUST auf ausdrückliche Anfrage Gewichtsproben des gewählten Zeitraums mit Einheit, Messzeit und Quelle zur Auswahl anzeigen. Erst ausdrückliche Bestätigung DARF daraus eigene Check-ins mit atomarer Outbox machen. Dieselbe Health-Probe MUST pro Gainer-Konto wiederholbar ohne Duplikat behandelt werden; bestehende Check-ins DÜRFEN nicht still überschrieben werden. Vor Bestätigung MUST die App erklären, dass bestätigte Check-ins in den eigenen Gainer-Server-Sync gelangen.

#### Scenario: Messung prüfen und übernehmen
- **GIVEN** eine gültige Health-Gewichtsprobe und Konto A als aktiver Writer
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

### Requirement: Expliziter idempotenter Workout-Export

Die App MUST ausschließlich eigene abgeschlossene Workouts nach ausdrücklicher Bestätigung nach Apple Health exportieren. Sie MUST Beginn, Ende und Trainingsart korrekt abbilden, unbekannte Energie-/Pulswerte weglassen und wiederholte Exportversuche anhand einer stabilen Zuordnung ohne Duplikate behandeln. Health-Ausfall DARF Gainer-Speichern oder Sync nicht zurückrollen. Exportierte Health-Einträge DÜRFEN durch Kontoabmeldung nicht pauschal gelöscht werden.

#### Scenario: Export verliert lokale Bestätigung
- **GIVEN** ein Workout wurde nach Health geschrieben, aber die App endet vor lokaler Bestätigung
- **WHEN** derselbe Export erneut angefordert wird
- **THEN** erkennt die App den bereits zugeordneten Export und erstellt kein zweites Workout

#### Scenario: Health-Schreibzugriff fehlt
- **GIVEN** ein abgeschlossenes Gainer-Workout ohne Health-Schreibzugriff
- **WHEN** der Nutzer exportieren möchte
- **THEN** zeigt die App einen fehlgeschlagenen oder nicht erlaubten Export mit Wiederholungsmöglichkeit und behält Workout, Historie und Sync unverändert
