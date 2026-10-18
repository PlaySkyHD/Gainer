# sync-force-local

## ADDED Requirements

### Requirement: Lokalen Stand erzwingen

Für einen Sync-Konflikt SHALL der Nutzer den aktuellen lokalen Stand der Ressource erzwingen können. Die App MUST alle wartenden Änderungen dieser Ressource durch eine Änderung ersetzen, die den lokalen Stand überträgt, und MUST Server-Löschungen nicht wiederbeleben.

#### Scenario: Altes aktives Training
- **GIVEN** ein Konflikt „active_workout_exists“ für ein Training, das lokal inzwischen beendet ist und auf dem Server nicht existiert
- **WHEN** der Nutzer „Lokalen Stand erzwingen“ wählt und bestätigt
- **THEN** sendet die App das beendete Training als Neuanlage und der Konflikt verschwindet nach erfolgreichem Sync

#### Scenario: Lokal gelöscht und nie auf dem Server
- **GIVEN** ein Konflikt für ein Training, das lokal gelöscht ist und auf dem Server nie existierte
- **WHEN** der Nutzer den lokalen Stand erzwingt
- **THEN** werden Konflikt und wartende Änderungen entfernt und nichts gesendet

### Requirement: Konflikte gesammelt lösen

Die Konfliktliste SHALL eine Mehrfachauswahl mit „Alle auswählen“ bieten. Gesammeltes Erzwingen MUST in der ursprünglichen Reihenfolge der Änderungen erfolgen und anschließend synchronisieren.

#### Scenario: Übung vor Training
- **GIVEN** Konflikte für eine eigene Übung und ein Training, das diese Übung nutzt
- **WHEN** der Nutzer beide auswählt und erzwingt
- **THEN** wird die Übung vor dem Training gesendet

### Requirement: Verständliche Konfliktgründe

Jede Konfliktzeile SHALL den Namen der Ressource und einen deutschen Grund zeigen. „Serverstand nutzen“ MUST nur angeboten werden, wenn ein Serverstand vorhanden ist.

#### Scenario: Ohne Serverstand
- **GIVEN** ein Konflikt für ein Training, das der Server nie hatte
- **WHEN** die Konfliktliste angezeigt wird
- **THEN** fehlt „Serverstand nutzen“ und „Lokalen Stand erzwingen“ ist verfügbar
