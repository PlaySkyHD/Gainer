## Purpose

Diese Capability ermöglicht die nachvollziehbare Verwaltung eines aktuellen Körperziels sowie schnelle tägliche Körper- und Ernährungs-Check-ins mit sicheren Korrekturen.

## ADDED Requirements

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

Das System SHALL je Check-in einen lokalen Kalendertag, ein positives endliches Körpergewicht und Erstellungszeitpunkt speichern. Es SHALL optional nicht negative endliche Werte für Kalorien, Protein, Kohlenhydrate und Fett, eine nicht negative ganze Schrittzahl sowie eine Schlafdauer zwischen 0 und 24 Stunden akzeptieren.

#### Scenario: Check-in nur mit Pflichtwerten

- **GIVEN** ein authentifizierter Nutzer hat für den gewählten Kalendertag noch keinen Check-in
- **WHEN** er ein gültiges Körpergewicht übermittelt
- **THEN** wird ein Check-in für diesen Nutzer und Kalendertag mit einem Erstellungszeitpunkt gespeichert

#### Scenario: Check-in mit optionalen Tageswerten

- **GIVEN** ein Nutzer übermittelt neben dem Gewicht gültige Ernährungs-, Schritt- und Schlafwerte
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
