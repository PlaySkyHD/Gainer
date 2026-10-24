## ADDED Requirements

### Requirement: Export der eigenen Daten

Das System SHALL einem angemeldeten Nutzer alle eigenen fachlichen Daten als eine JSON-Datei bereitstellen: den aktuellen Stand jeder eigenen Sync-Ressource, ohne gelöschte Ressourcen und nur für den aus der Sitzung bestimmten Nutzer. Der Export MUST NOT Passwörter, Passkeys, Sessions, Tokens, Geräte oder Integrationszugänge enthalten. Die Datei SHALL Format-Kennzeichen, Schemaversion, Exportzeitpunkt und Server-Revision tragen. Der Endpunkt MUST pro Nutzer begrenzt sein.

#### Scenario: Vollständiger Export

- **GIVEN** ein Nutzer hat Trainings, Ernährungstage und Check-ins, eine Ressource mehrfach geändert und eine gelöscht
- **WHEN** er den Export anfordert
- **THEN** enthält die Datei jede vorhandene Ressource genau einmal in ihrer neuesten Version und die gelöschte nicht

#### Scenario: Keine fremden Daten

- **GIVEN** zwei Nutzer haben Daten
- **WHEN** der erste Nutzer exportiert
- **THEN** enthält die Datei keine Ressource des zweiten Nutzers

### Requirement: Datenexport in der App

Die App SHALL den Export unter „Mehr“ anbieten und als Datei über das iOS-Teilen-Sheet weitergeben. Sie SHALL ihn nur mit Verbindung anbieten und auf noch nicht gesendete Änderungen hinweisen.

#### Scenario: Ohne Verbindung

- **GIVEN** die App ist offline
- **WHEN** der Nutzer den Export-Screen öffnet
- **THEN** ist „Export erstellen“ deaktiviert und der Screen nennt den Grund

#### Scenario: Noch nicht gesendete Änderungen

- **GIVEN** das Gerät hat Änderungen, die noch nicht beim Server sind
- **WHEN** der Nutzer den Export-Screen öffnet
- **THEN** weist der Screen darauf hin, dass diese Änderungen im Export fehlen

#### Scenario: Zu viele Exporte

- **GIVEN** ein Nutzer hat das Export-Limit im aktuellen Zeitfenster ausgeschöpft
- **WHEN** er erneut exportiert
- **THEN** antwortet der Server mit `429` und die App zeigt einen Hinweis zum späteren Versuch
