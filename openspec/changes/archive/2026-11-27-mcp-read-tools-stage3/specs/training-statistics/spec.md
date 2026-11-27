## ADDED Requirements

### Requirement: Gleiche Kennzahlen in App und Server

Rechnet die App eine Kennzahl selbst, MUST der Server sie für den MCP-Server nach denselben Regeln rechnen: Verlauf, Trainingstage, Muskelvolumen, Cardio-Kennzahlen und Ernährungsdurchschnitt. Je Berechnung SHALL eine gemeinsame Fixture unter `contracts/fixtures/` Eingaben und Ergebnisse festhalten, die Tests der App und des Servers gleichermaßen prüfen. Nur Werte aus Einstellungen, die allein auf dem Telefon liegen, DÜRFEN fehlen.

#### Scenario: Fixture des Verlaufs
- **GIVEN** die Fixture `training-trends.json` mit Wochen über das Ende der Sommerzeit und Aufwärmsätzen
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide dieselben Abschnitte, Summen und Durchschnitte

#### Scenario: Automatische Tagesart
- **GIVEN** ein erfasster Ernährungstag ohne festgelegte Tagesart unter einem Ziel mit Ruhetag-Ziel
- **WHEN** der Server den Ernährungsdurchschnitt rechnet
- **THEN** gilt das Trainingstag-Ziel, weil die Tagesart aus dem Trainingsrhythmus nur die App ableitet
