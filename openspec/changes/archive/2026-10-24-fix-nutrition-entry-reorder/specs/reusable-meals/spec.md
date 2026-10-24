# reusable-meals

## MODIFIED Requirements

### Requirement: Gerichte unabhängig vom Ernährungstag pflegen

Die Anwendung MUST im Ernährungsbereich eine eigenständige Gerichtebibliothek bereitstellen, die ohne Öffnen eines Lebensmittel-Hinzufügen-Dialogs erreichbar ist. Dort MUST der Nutzer aktive und archivierte eigene Gerichte anzeigen, neue Gerichte anlegen sowie bestehende Gerichte bearbeiten, duplizieren und archivieren können. Der Hinzufügen-Dialog eines Ernährungstags MUST dieselben aktiven Gerichtsvorlagen verwenden, DARF aber nicht der einzige Zugang zur Pflege sein.

#### Scenario: Gericht ohne geöffneten Ernährungstag anlegen

- **GIVEN** ein Nutzer befindet sich in der eigenständigen Gerichtebibliothek
- **WHEN** er ein gültiges Gericht mit mehreren Komponenten speichert
- **THEN** erscheint es unmittelbar in seiner Bibliothek und steht anschließend in der Gerichteauswahl eines Ernährungstags zur Verfügung

#### Scenario: Gericht duplizieren

- **GIVEN** ein Nutzer besitzt das Gericht „Chicken Rice Bowl“
- **WHEN** er es in der Gerichtebibliothek dupliziert
- **THEN** entsteht ein neues eigenes Gericht mit neuer stabiler ID und unabhängigen Komponenten-Snapshots, das vor dem Speichern bearbeitet werden kann

#### Scenario: Archivierte Gerichte verwalten

- **GIVEN** ein Nutzer hat ein Gericht archiviert
- **WHEN** er in der Gerichtebibliothek archivierte Gerichte einblendet
- **THEN** kann er dessen gespeicherte Komponenten weiterhin ansehen, während das Gericht in keinem Ernährungstag neu angeboten wird

#### Scenario: Komponenten umsortieren oder entfernen

- **GIVEN** ein Gericht hat drei Komponenten
- **WHEN** der Nutzer die erste entfernt oder zwei Komponenten tauscht und speichert
- **THEN** übernimmt der Server den Stand mit denselben Komponenten-IDs und meldet keinen Konflikt
