## MODIFIED Requirements

### Requirement: Gleiche Kennzahlen in App und Server

Rechnet die App eine Kennzahl selbst, MUST der Server sie für den MCP-Server gleich rechnen: Verlauf, Trainingstage, Muskelvolumen, Cardio-Kennzahlen, Ernährungsdurchschnitt und Rhythmus-Vorschau mit Tagesart. Je Berechnung SHALL eine Fixture unter `contracts/fixtures/` Eingaben und Ergebnisse festhalten, die App- und Server-Tests prüfen. Nur Werte aus Einstellungen, die allein auf dem Telefon liegen, DÜRFEN fehlen.

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
