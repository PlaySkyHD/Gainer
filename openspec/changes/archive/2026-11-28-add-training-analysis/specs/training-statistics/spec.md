## ADDED Requirements

### Requirement: Trainingsanalyse im Statistikbereich

Die App SHALL im Statistikbereich einen Eintrag „Trainingsanalyse“ anbieten. Der Screen MUST einen Zeitraum-Umschalter (4 W, 3 M, 1 J; Standard 3 M), einen Gesamtteil mit Wochenvolumen-Trend und Ermüdung sowie je Übung des Zeitraums Status, Empfehlung und Ermüdungshinweis zeigen. Das Detail einer Übung SHALL Empfehlung mit Begründung, Trends, Ermüdungssignale mit Belegen und die Einheiten zeigen. Die Daten MUST aus dem lokalen Speicher kommen.

#### Scenario: Analyse öffnen
- **GIVEN** der Nutzer hat in den letzten drei Monaten Bankdrücken und Kreuzheben trainiert
- **WHEN** er in der Statistik „Trainingsanalyse“ öffnet
- **THEN** zeigt die Liste beide Übungen mit Status-Badge und Empfehlung, die zuletzt trainierte zuerst

#### Scenario: Große Schrift
- **GIVEN** die Textgröße ist 2,0
- **WHEN** Liste und Detail erscheinen
- **THEN** steht der Status in der Unterzeile statt als Badge und nichts läuft über

### Requirement: Fortschrittsstatus einer Übung

Die Trainingsanalyse MUST je Übung die Einheiten (Trainings mit mindestens einem Arbeitssatz ohne Aufwärmsätze) zählen und das geschätzte 1RM des ersten Drittels mit dem des letzten Drittels der Einheiten vergleichen (je mindestens eine Einheit). Unter drei Einheiten SHALL der Status „Zu wenig Daten“ sein, bei einer Änderung von höchstens −2,5 % „Sinkt“, bei mindestens +2,5 % und einem Bestwert in den letzten drei Einheiten „Steigt“, sonst „Stagniert“.

#### Scenario: Plateau nach Anstieg
- **GIVEN** sieben Einheiten Kniebeuge mit je 3 × 5 bei 100 kg
- **WHEN** die Analyse rechnet
- **THEN** ist der Status „Stagniert“ mit sechs Einheiten seit dem Bestwert

### Requirement: Ermüdungssignale

Die Trainingsanalyse MUST Ermüdung als Signale mit Belegen melden: sinkende Wiederholungen der Topsätze zweimal in Folge bei gleichem oder geringerem Gewicht, RIR 0 bei mehr als der Hälfte der bewerteten Arbeitssätze in zwei Einheiten in Folge, sowie mindestens 20 % weniger Volumen und 5 % weniger 1RM der letzten Einheit gegenüber dem Mittel der bis zu drei Einheiten davor.

#### Scenario: Kreuzheben ermüdet
- **GIVEN** Kreuzheben mit 3 × 6, 3 × 5 und 3 × 4 bei 140 kg und danach 3 × 3 bei 135 kg, die letzten zwei Einheiten mit RIR 0 in allen Sätzen
- **WHEN** die Analyse rechnet
- **THEN** meldet sie alle drei Signale und der Gesamtteil zeigt erhöhte Ermüdung

### Requirement: Empfehlung je Übung

Die Trainingsanalyse SHALL je Übung eine regelbasierte Empfehlung mit deutscher Begründung geben: bei Ermüdung oder sinkender Leistung Deload auf 90 % des eingetragenen Gewichts, auf die Gewichtsstufe abgerundet; bei Stagnation seit mindestens vier Einheiten einen Reizwechsel; sonst doppelte Progression im Wiederholungsbereich der letzten Einheit (3–5, 6–12 oder 13–20).

#### Scenario: Gewicht erhöhen
- **GIVEN** die letzte Einheit Bankdrücken war 3 × 12 bei 90 kg und im Zeitraum wurde in 2,5-kg-Schritten gesteigert
- **WHEN** die Analyse rechnet
- **THEN** lautet die Empfehlung „Oberes Ende von 6–12 Wdh. in allen Sätzen erreicht: nächstes Mal 92,5 kg mit 6 Wdh.“

#### Scenario: Deload
- **GIVEN** das Kreuzheben aus „Kreuzheben ermüdet“
- **WHEN** die Analyse rechnet
- **THEN** empfiehlt sie einen Deload auf 120 kg (90 % von 135 kg, auf 2,5 kg abgerundet)

### Requirement: Gewichtsstufe der Empfehlung

Die Gewichtsstufe einer Empfehlung MUST der kleinste positive Abstand der eingetragenen Gewichte der Übung im Zeitraum sein, höchstens 2,5 kg; ohne Abstand gilt 2,5 kg.

#### Scenario: Kleinere Stufe
- **GIVEN** Dips mit 10 kg und danach 3 × 12 mit 12 kg Zusatzgewicht
- **WHEN** die Analyse rechnet
- **THEN** empfiehlt sie 14 kg, weil die kleinste genutzte Stufe 2 kg ist

## MODIFIED Requirements

### Requirement: Gleiche Kennzahlen in App und Server

Rechnet die App eine Kennzahl selbst, MUST der Server sie für den MCP-Server gleich rechnen: Verlauf, Trainingstage, Muskelvolumen, Cardio-Kennzahlen, Ernährungsdurchschnitt, Rhythmus-Vorschau mit Tagesart und Trainingsanalyse. Je Berechnung SHALL eine Fixture unter `contracts/fixtures/` Eingaben und Ergebnisse festhalten, die App- und Server-Tests prüfen. Nur Werte aus Einstellungen, die allein auf dem Telefon liegen, DÜRFEN fehlen.

#### Scenario: Fixture des Verlaufs
- **GIVEN** die Fixture `training-trends.json` mit Wochen über das Ende der Sommerzeit und Aufwärmsätzen
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide dieselben Abschnitte, Summen und Durchschnitte

#### Scenario: Automatische Tagesart
- **GIVEN** ein erfasster Ernährungstag ohne festgelegte Tagesart unter einem Ziel mit Ruhetag-Ziel
- **WHEN** der Server den Ernährungsdurchschnitt rechnet
- **THEN** leitet der Server die Tagesart wie die App aus beendeten Trainings und der Rhythmus-Vorschau ab und nutzt am Ruhetag das Ruhetag-Ziel

#### Scenario: Fixture der Rhythmus-Vorschau
- **GIVEN** die Fixture `training-schedule.json` mit Zyklus und festen Tagen, Verschiebungen, Überspringen, archivierten Plänen und Trainings rund um Mitternacht und die Zeitumstellung
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide je Tag dieselbe Tagesart, dieselben Trainings mit Status und dieselbe automatische Tagesart sowie dasselbe nächste offene Training

#### Scenario: Fixture der Trainingsanalyse
- **GIVEN** die Fixture `training-analysis.json` mit Fortschritt, Stagnation, Rückschritt mit Ermüdung, Körpergewichtsübungen und Aufwärmsätzen
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide dieselben Einheiten, Trends, Status, Signale, Empfehlungen mit identischem Begründungstext und denselben Gesamtteil
