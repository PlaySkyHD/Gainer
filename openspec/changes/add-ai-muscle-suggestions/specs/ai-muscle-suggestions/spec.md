# ai-muscle-suggestions

## ADDED Requirements

### Requirement: Muskeln im Dialog mit der KI ermitteln

Der Übungseditor SHALL für bearbeitbare Übungen mit Namen „Mit KI ermitteln“ anbieten. Die KI SHALL entweder höchstens zwei Rückfragen mit Antwort-Optionen stellen oder Haupt- und Hilfsmuskeln aus den 17 Muskel-Schlüsseln mit kurzer Begründung vorschlagen. Ein Vorschlag MUST erst nach „Übernehmen“ in den Editor gelangen und MUST NOT automatisch gespeichert werden.

#### Scenario: Rückfrage und Vorschlag
- **GIVEN** eine eigene Übung „Rudern Maschine“
- **WHEN** der Nutzer „Mit KI ermitteln“ tippt, die KI nach dem Griff fragt und er „Eng“ wählt
- **THEN** zeigt das Sheet einen Vorschlag auf der Körperkarte, und nach „Übernehmen“ stehen die Muskeln im Editor

#### Scenario: Höchstens zwei Rückfragen
- **GIVEN** zwei beantwortete Rückfragen
- **WHEN** die App erneut anfragt
- **THEN** antwortet der Server nur mit einem Vorschlag oder einem Fehler

### Requirement: Kontingent und Fehler

Der Server SHALL KI-Anfragen pro Nutzer und Tag begrenzen und bei Überschreitung 429 mit `daily_budget_exhausted` antworten. Die App MUST Fehler verständlich anzeigen und einen erneuten Versuch anbieten.

#### Scenario: Tageslimit
- **GIVEN** das Tageslimit ist erreicht
- **WHEN** der Nutzer „Mit KI ermitteln“ tippt
- **THEN** zeigt das Sheet „Das Tageslimit für KI-Anfragen ist erreicht. Morgen geht es wieder.“
