# plan-entry-menu

## ADDED Requirements

### Requirement: Übungsmenü im Planeditor

Jeder Eintrag im Planeditor SHALL ein Übungsmenü mit Verschieben, Ersetzen, Löschen und „Sätze bearbeiten“ bieten, erreichbar über den „…“-Knopf und langes Drücken. Bei nur einem Eintrag MUST „Verschieben“ fehlen. Änderungen MUST erst mit „Speichern“ gespeichert werden.

#### Scenario: Verschieben
- **GIVEN** ein Plan mit Latzug, TBar und HighRow
- **WHEN** der Nutzer HighRow im Neuordnen-Sheet an den Anfang zieht, „Fertig“ und dann „Speichern“ tippt
- **THEN** ist die gespeicherte Reihenfolge HighRow, Latzug, TBar

#### Scenario: Ersetzen
- **GIVEN** ein Eintrag „Latzug“ mit 3 Arbeitssätzen
- **WHEN** der Nutzer „Ersetzen“ wählt, „Klimmzug“ auswählt und speichert
- **THEN** steht an derselben Stelle „Klimmzug“ mit 3 Arbeitssätzen und derselben Eintrags-ID

#### Scenario: Nur ein Eintrag
- **GIVEN** ein Plan mit genau einem Eintrag
- **WHEN** der Nutzer das Übungsmenü öffnet
- **THEN** fehlt „Verschieben“, „Ersetzen“ wird angeboten

### Requirement: Superset auflösen

Ein Superset-Eintrag, der nach Verschieben oder Löschen keinen Nachbarn desselben Supersets mehr hat, SHALL zu einer normalen Übung werden.

#### Scenario: Löschen trennt Superset
- **GIVEN** TBar und HighRow bilden ein Superset
- **WHEN** der Nutzer TBar löscht und speichert
- **THEN** ist HighRow keinem Superset mehr zugeordnet
