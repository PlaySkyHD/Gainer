# ai-coach

## MODIFIED Requirements

### Requirement: Verwaltung des Coach-Gedächtnisses

Der Nutzer SHALL Gedächtniseinträge (Kategorie `goal`, `preference`, `intolerance`, `injury` oder `other`, Text mit 1 bis 200 UTF-16-Einheiten) auflisten, anlegen, bearbeiten, einzeln und alle löschen können. Das System MUST höchstens 50 Einträge je Nutzer ohne Ablaufdatum zulassen und Änderungen mit veralteter Basisversion ablehnen. Ohne Verbindung oder bei vollem Gedächtnis MUST die App betroffene Änderungen sperren und den Grund nennen.

#### Scenario: Nutzer löscht einen Eintrag oder alles

- **GIVEN** ein Nutzer hat drei Einträge
- **WHEN** er einen Eintrag löscht und danach „Alles vergessen“ bestätigt
- **THEN** ist das Gedächtnis leer und spätere Coach-Anfragen enthalten keine dieser Notizen

#### Scenario: Grenze erreicht

- **GIVEN** ein Nutzer hat 50 Einträge
- **WHEN** er einen weiteren Eintrag anlegen will
- **THEN** lehnt der Server mit dem Code `memory_limit_reached` ab und kein Eintrag kommt hinzu, und die App sperrt „Merken“ und „Hinzufügen“ mit Hinweis

#### Scenario: Gleicher Text mit anderer Kategorie

- **GIVEN** das Gedächtnis enthält „Laktoseintoleranz“ als `other`
- **WHEN** der Nutzer denselben Text als `intolerance` merkt
- **THEN** hat der vorhandene Eintrag danach die Kategorie `intolerance` und eine höhere Version, der Server antwortet mit 200, und der Eintrag bleibt an seiner Stelle in der Liste

#### Scenario: Gleichzeitige Änderung

- **GIVEN** zwei Geräte bearbeiten denselben Eintrag in Version 1
- **WHEN** beide ihre Änderung mit Basisversion 1 senden
- **THEN** gilt nur die erste, die zweite erhält 409 mit dem Code `memory_conflict`, und die App erklärt das und lädt die Liste neu, ohne den getippten Text zu verwerfen

#### Scenario: Fremder Nutzer sieht keine Einträge

- **GIVEN** Nutzer A hat Gedächtniseinträge
- **WHEN** Nutzer B die Liste abruft oder die ID eines Eintrags von A ändert oder löscht
- **THEN** sieht B keine Einträge von A, und Änderung oder Löschung antworten wie bei einer unbekannten ID mit 404

#### Scenario: Ohne Verbindung

- **GIVEN** die App ist offline
- **WHEN** der Nutzer das Gedächtnis öffnet oder unter einer Antwort einen Vorschlag sieht
- **THEN** sind Hinzufügen, Bearbeiten, Löschen und „Merken“ gesperrt, und ein Hinweis nennt die fehlende Verbindung als Grund
