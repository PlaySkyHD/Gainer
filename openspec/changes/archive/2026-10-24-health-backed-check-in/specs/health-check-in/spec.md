# health-check-in

## ADDED Requirements

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
