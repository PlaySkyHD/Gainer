# meal-dictation

## ADDED Requirements

### Requirement: Mahlzeit diktieren

Das Sheet „Mahlzeit schätzen“ SHALL einen Button „Diktieren“ anbieten, der die Beschreibung per Spracherkennung auf dem Gerät füllt. Audio MUST NOT das Gerät verlassen. Der erkannte Text SHALL live im Feld erscheinen und an vorhandenen Text angehängt werden. Die Schätzung MUST erst auf „Mahlzeit schätzen“ starten.

#### Scenario: Diktat füllt die Beschreibung
- **GIVEN** das Sheet „Mahlzeit schätzen“ ist offen
- **WHEN** der Nutzer „Diktieren“ tippt und „Zwei Eier und ein Toast“ sagt
- **THEN** steht der Text im Feld „Beschreibung“ und der Button heißt „Fertig“

#### Scenario: Schätzen während der Aufnahme
- **GIVEN** ein laufendes Diktat
- **WHEN** der Nutzer „Mahlzeit schätzen“ tippt
- **THEN** endet die Aufnahme und die Schätzung nutzt den endgültigen Text

### Requirement: Rechte und Verfügbarkeit

Lehnt der Nutzer Mikrofon oder Spracherkennung ab oder fehlt die Erkennung auf dem Gerät, SHALL die App einen Hinweis mit dem Weg in die Einstellungen zeigen und MUST NOT aufnehmen. Ohne Diktat-Plattform MUST der Button fehlen.

#### Scenario: Rechte abgelehnt
- **GIVEN** die Spracherkennung ist in den Einstellungen nicht erlaubt
- **WHEN** der Nutzer „Diktieren“ tippt
- **THEN** zeigt das Sheet „Erlaube Mikrofon und Spracherkennung in den iOS-Einstellungen, um zu diktieren.“
