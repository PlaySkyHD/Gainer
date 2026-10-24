# body-tracking Specification

## Purpose
Körperziel und tägliche Check-ins mit Gewicht, Schlaf und Schritten, verbunden mit Apple Health: Werte vorausfüllen und zurückschreiben, Gewicht prüfen und importieren, abgeschlossene Workouts exportieren.

## Requirements

### Requirement: Körperziel verwalten

Das System SHALL ein Körperziel mit Zielart, positivem Startgewicht, positivem Zielgewicht, Startdatum und optionalem Zieldatum speichern. Die Zielart MUST `Bulk`, `Maintain` oder `Cut` sein.

#### Scenario: Gültiges Ziel anlegen

- **GIVEN** ein authentifizierter Nutzer besitzt kein aktives Körperziel
- **WHEN** er eine gültige Zielart, Start- und Zielgewicht sowie ein gültiges Startdatum übermittelt
- **THEN** wird das Ziel diesem Nutzer zugeordnet und als aktiv gespeichert

#### Scenario: Ungültiges Ziel ablehnen

- **GIVEN** die Zielart ist unbekannt, ein Gewicht ist nicht positiv oder endlich oder das Zieldatum liegt vor dem Startdatum
- **WHEN** das Ziel gespeichert werden soll
- **THEN** wird die gesamte Änderung mit feldbezogenen Fehlern abgelehnt und kein Ziel gespeichert

### Requirement: Genau ein aktives Ziel und erhaltene Zielhistorie

Das System MUST pro Nutzer höchstens ein aktives Körperziel führen und SHALL vergangene Ziele mit ihren ursprünglichen Zielwerten und Zeitangaben erhalten.

#### Scenario: Neues Ziel ersetzt das aktive Ziel

- **GIVEN** ein Nutzer besitzt bereits ein aktives Ziel
- **WHEN** er ein neues gültiges Ziel aktiviert
- **THEN** wird das bisherige Ziel beendet und in der Historie erhalten, während ausschließlich das neue Ziel aktiv ist

#### Scenario: Zielhistorie abrufen

- **GIVEN** ein Nutzer besitzt ein aktives und mehrere vergangene Ziele
- **WHEN** er seine Ziele abruft
- **THEN** erhält er genau ein als aktiv gekennzeichnetes Ziel und ausschließlich seine unverändert erhaltenen vergangenen Ziele

### Requirement: Täglichen Check-in erfassen

Das System SHALL je Check-in einen lokalen Kalendertag, ein positives endliches Körpergewicht und Erstellungszeitpunkt speichern. Es SHALL optional eine nicht negative ganze Schrittzahl, eine Schlafdauer zwischen 0 und 24 Stunden sowie Ruhepuls und HRV akzeptieren. Kalorien und Makros früherer Check-ins SHALL der Server weiter annehmen; die App erfasst sie dort nicht mehr.

#### Scenario: Check-in nur mit Pflichtwerten

- **GIVEN** ein authentifizierter Nutzer hat für den gewählten Kalendertag noch keinen Check-in
- **WHEN** er ein gültiges Körpergewicht übermittelt
- **THEN** wird ein Check-in für diesen Nutzer und Kalendertag mit einem Erstellungszeitpunkt gespeichert

#### Scenario: Check-in mit optionalen Tageswerten

- **GIVEN** ein Nutzer übermittelt neben dem Gewicht gültige Schritt- und Schlafwerte
- **WHEN** der Check-in gespeichert wird
- **THEN** werden genau die übermittelten optionalen Werte gemeinsam mit Gewicht, Kalendertag und Zeitstempel gespeichert

#### Scenario: Ungültige Check-in-Werte

- **GIVEN** das Gewicht fehlt oder ein numerischer Wert ist nicht endlich, negativ oder außerhalb seiner definierten Grenze
- **WHEN** der Check-in gespeichert werden soll
- **THEN** wird die gesamte Änderung mit feldbezogenen Fehlern abgelehnt und kein Teilwert gespeichert

### Requirement: Ein Check-in pro Nutzer und Kalendertag

Das System MUST je Nutzer und lokalem Kalendertag höchstens einen täglichen Check-in speichern und MUST parallele oder wiederholte Neuanlagen eines zweiten Check-ins verhindern.

#### Scenario: Doppelten Check-in ablehnen

- **GIVEN** für einen Nutzer existiert bereits ein Check-in am gewählten Kalendertag
- **WHEN** er einen weiteren Check-in mit einer anderen ID für denselben Tag anlegt
- **THEN** antwortet die API mit `409 Conflict` und der vorhandene Check-in bleibt unverändert

#### Scenario: Gleicher Kalendertag bei verschiedenen Nutzern

- **GIVEN** Nutzer A besitzt bereits einen Check-in für einen Kalendertag
- **WHEN** Nutzer B für denselben Kalendertag seinen ersten Check-in anlegt
- **THEN** wird der Check-in für Nutzer B unabhängig gespeichert

### Requirement: Eigenen Check-in korrigieren

Das System SHALL einem Nutzer erlauben, Werte seines bestehenden Check-ins zu korrigieren, ohne für denselben Nutzer und Tag einen zusätzlichen Datensatz anzulegen. Eine erfolgreiche Korrektur MUST den Änderungszeitpunkt aktualisieren und den Erstellungszeitpunkt erhalten.

#### Scenario: Gültige Korrektur speichern

- **GIVEN** ein Nutzer besitzt einen Check-in mit stabiler ID
- **WHEN** er dessen Gewicht oder optionale Tageswerte durch gültige Werte ersetzt
- **THEN** wird derselbe Datensatz vollständig aktualisiert und kein zweiter Check-in erzeugt

#### Scenario: Ungültige Korrektur verwerfen

- **GIVEN** ein vorhandener Check-in enthält gültige Werte
- **WHEN** der Nutzer eine Korrektur mit ungültigen Werten sendet
- **THEN** bleibt der zuvor gespeicherte Check-in vollständig unverändert

### Requirement: Isolation von Zielen und Check-ins

Das System MUST Ziele und Check-ins anhand des authentifizierten Nutzers lesen und verändern und SHALL fremde Ressourcen wie nicht vorhandene Ressourcen behandeln.

#### Scenario: Fremdes Ziel abrufen

- **GIVEN** Nutzer A ist authentifiziert und kennt die ID eines Ziels von Nutzer B
- **WHEN** Nutzer A dieses Ziel abruft
- **THEN** antwortet die API mit `404 Not Found` und gibt keine Zieldaten zurück

#### Scenario: Fremden Check-in korrigieren

- **GIVEN** Nutzer A ist authentifiziert und kennt die ID eines Check-ins von Nutzer B
- **WHEN** Nutzer A eine Korrektur sendet
- **THEN** antwortet die API mit `404 Not Found` und der Check-in von Nutzer B bleibt unverändert

### Requirement: Schlanker Check-in

Der Check-in SHALL nur Datum, Gewicht, Schlaf und Schritte zeigen. Kalorien, Protein, Kohlenhydrate und Fett MUST NOT mehr eingegeben werden; vorhandene Werte alter Check-ins bleiben beim Speichern erhalten.

#### Scenario: Neuer Check-in
- **GIVEN** der Nutzer öffnet einen neuen Check-in
- **WHEN** das Sheet erscheint
- **THEN** gibt es Felder für Gewicht und Schlaf, eine Anzeige für Schritte und keine Felder für Kalorien oder Makros

### Requirement: Gewicht aus und nach Apple Health

Das Gewicht SHALL mit dem jüngsten Apple-Health-Wert des Check-in-Tags vorausgefüllt werden und editierbar bleiben. Liegt für den Tag kein Health-Wert einer anderen Quelle vor, MUST das gespeicherte Gewicht nach Apple Health geschrieben werden, ohne bei erneutem Speichern Duplikate zu erzeugen.

#### Scenario: Vorausgefülltes Gewicht
- **GIVEN** Apple Health enthält für heute 81,4 kg
- **WHEN** der Nutzer den Check-in öffnet
- **THEN** steht 81,4 im Gewichtsfeld mit dem Hinweis „aus Apple Health“

#### Scenario: Gewicht nach Health schreiben
- **GIVEN** Apple Health enthält für heute kein Gewicht
- **WHEN** der Nutzer 80,9 kg speichert und danach auf 81,0 kg korrigiert
- **THEN** enthält Apple Health genau eine Gainer-Probe mit 81,0 kg

### Requirement: Schlaf als Zu-Bett- und Aufstehzeit

Schlaf SHALL über „Zu Bett“ und „Aufgestanden“ erfasst und als Dauer in Minuten gespeichert werden. Eine vorhandene Schlafanalyse der vorangehenden Nacht MUST die Zeiten vorausfüllen. Ohne fremde Schlafdaten MUST manuell erfasster Schlaf nach Apple Health geschrieben werden.

#### Scenario: Schlaf aus Health
- **GIVEN** Apple Health enthält Schlaf von 23:10 bis 6:45
- **WHEN** der Nutzer den Check-in öffnet
- **THEN** stehen 23:10 und 6:45 in den Zeilen und die Dauer lautet „7 h 35 min“

#### Scenario: Schlaf über Mitternacht
- **GIVEN** der Nutzer wählt Zu Bett 23:30 und Aufgestanden 7:00
- **WHEN** er speichert
- **THEN** werden 450 Minuten gespeichert

### Requirement: Schritte nur aus Apple Health

Schritte SHALL als Tagessumme aus Apple Health angezeigt und mit dem Check-in gespeichert werden. Eine manuelle Eingabe MUST NOT angeboten werden.

#### Scenario: Keine Schrittdaten
- **GIVEN** Apple Health liefert keine Schritte für den Tag
- **WHEN** der Check-in angezeigt wird
- **THEN** steht dort „Keine Daten aus Apple Health“ und Schritte bleiben leer

### Requirement: Health-Fehler blockieren nicht

Fehlende Berechtigungen oder Fehler beim Lesen oder Schreiben von Apple Health MUST NOT das Speichern des Check-ins verhindern.

#### Scenario: Schreiben verweigert
- **GIVEN** der Nutzer hat das Schreiben nach Health abgelehnt
- **WHEN** er einen Check-in speichert
- **THEN** wird der Check-in gespeichert und es erscheint kein Fehler

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
