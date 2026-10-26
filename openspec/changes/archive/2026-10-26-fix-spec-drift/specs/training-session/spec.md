## MODIFIED Requirements

### Requirement: Training beenden mit Fehlwerte-Dialog

Beim Beenden MUST das System prüfen, ob Sätze fehlende Pflichtwerte haben. Gibt es solche Sätze, SHALL ein Dialog die Optionen „Ja, Vorwerte verwenden“, „Trotzdem beenden“ und „Weitertrainieren“ anbieten. Ohne fehlende Werte wird direkt beendet.

#### Scenario: Vorwerte übernehmen
- **GIVEN** ein Satz ohne Wiederholungen und mit vorhandenem Vorwert 100 kg × 8
- **WHEN** der Nutzer beendet und „Ja, Vorwerte verwenden“ wählt
- **THEN** werden nur die leeren Felder mit 100 kg beziehungsweise 8 gefüllt, bereits eingetragene Werte bleiben unverändert und die Endzeit wird gesetzt

#### Scenario: Vorwert fehlt bei Übernahme
- **GIVEN** ein leerer Satz ohne passenden Vorwert
- **WHEN** der Nutzer „Ja, Vorwerte verwenden“ wählt
- **THEN** bleiben dessen Felder leer und es wird weder 0 noch ein geschätzter Wert eingesetzt

#### Scenario: Trotzdem beenden
- **GIVEN** Sätze mit fehlenden Werten
- **WHEN** der Nutzer „Trotzdem beenden“ wählt
- **THEN** wird die Endzeit gesetzt und die fehlenden Werte bleiben leer

#### Scenario: Weitertrainieren
- **GIVEN** der Fehlwerte-Dialog ist offen
- **WHEN** der Nutzer „Weitertrainieren“ wählt
- **THEN** bleibt das Training ohne Endzeit aktiv und unverändert

### Requirement: Vorwertquelle

Jedes Training SHALL eine Vorwertquelle besitzen: „nach Übung“ (Standard), „nach Training“ oder „nach Plan“. „nach Plan“ ist nur wählbar, wenn das Training aus einem Plan gestartet wurde. Im Sheet „Training wiederholen“ heißen die Optionen „Aktuellste“ (nach Übung), „Wiederholtes Training“ (nach Training) und „Trainingsplan“ (nach Plan). Die Suche MUST nur nicht gelöschte eigene Trainings mit Start vor dem aktuellen Training berücksichtigen, neuestes zuerst, und bei Kraftübungen nur Blöcke mit mindestens einem Satz mit Wiederholungen größer 0.

#### Scenario: Nach Plan mit Fallback
- **GIVEN** ein aus Plan „Push“ gestartetes Training mit Quelle „nach Plan“ und keine frühere Einheit von „Push“ mit Seitheben
- **WHEN** Vorwerte für Seitheben ermittelt werden
- **THEN** stammen sie aus dem jüngsten geeigneten Training mit Seitheben unabhängig vom Plan

#### Scenario: Leere Blöcke überspringen
- **GIVEN** das jüngste Training mit Kniebeuge enthält nur leere Sätze und das davor 120 kg × 5
- **WHEN** Vorwerte nach Übung ermittelt werden
- **THEN** zeigt der Platzhalter 120 × 5

#### Scenario: Fremde Daten
- **GIVEN** Nutzer B hat dieselbe Basisübung trainiert, Nutzer A nie
- **WHEN** Nutzer A Vorwerte abruft
- **THEN** werden keine Werte von Nutzer B angezeigt

### Requirement: Plan- und Wiederholen-Ansichten

Der Planeditor SHALL einen großen Titel, darunter eine Karte „Training beginnen“, eine Karte mit Name, Vorwertquelle und Notizen, je eine Karte pro Eintrag mit Satzanzahl und „+ Übung hinzufügen“ zeigen. „Training wiederholen“ ist ein Sheet mit „Training beginnen“ und den Vorwertquellen „Aktuellste“, „Wiederholtes Training“ sowie, nur bei einem Training aus einem Plan, „Trainingsplan“, mit Haken an der gewählten.

#### Scenario: Vorwertquelle beim Wiederholen
- **GIVEN** das Sheet „Training wiederholen“ für ein Training vom 9. Oktober
- **WHEN** der Nutzer „Wiederholtes Training“ wählt und „Training beginnen“ tippt
- **THEN** startet ein neues Training, dessen Platzhalter die Werte vom 9. Oktober zeigen
