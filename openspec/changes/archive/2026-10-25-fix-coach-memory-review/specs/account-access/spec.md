# account-access

## MODIFIED Requirements

### Requirement: Export der eigenen Daten

Das System SHALL einem angemeldeten Nutzer alle eigenen Daten als JSON-Datei bereitstellen, nur für den aus der Sitzung bestimmten Nutzer: den aktuellen Stand jeder Sync-Ressource ohne gelöschte und im Abschnitt `coachMemories` alle Gedächtnis-Einträge. Der Export MUST NOT Passwörter, Passkeys, Sessions, Tokens, Geräte oder Integrationszugänge enthalten. Die Datei SHALL Format-Kennzeichen, Schemaversion, Exportzeitpunkt und Server-Revision tragen. Der Endpunkt MUST pro Nutzer begrenzt sein.

#### Scenario: Vollständiger Export

- **GIVEN** ein Nutzer hat Trainings, Ernährungstage und Check-ins, eine Ressource mehrfach geändert und eine gelöscht
- **WHEN** er den Export anfordert
- **THEN** enthält die Datei jede vorhandene Ressource genau einmal in ihrer neuesten Version und die gelöschte nicht

#### Scenario: Gedächtnis im Export

- **GIVEN** ein Nutzer hat zwei Einträge im Coach-Gedächtnis
- **WHEN** er den Export anfordert
- **THEN** enthält der Abschnitt `coachMemories` beide Einträge mit Kategorie, Text, Zeitstempeln und Version, neueste zuerst, und die Schemaversion bleibt 1

#### Scenario: Keine fremden Daten

- **GIVEN** zwei Nutzer haben Daten und Gedächtnis-Einträge
- **WHEN** der erste Nutzer exportiert
- **THEN** enthält die Datei keine Ressource und keinen Gedächtnis-Eintrag des zweiten Nutzers
