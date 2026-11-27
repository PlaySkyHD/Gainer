## ADDED Requirements

### Requirement: Übungen ohne Muskeln finden

Die Übungsverwaltung SHALL einen Schalter „Nur ohne Muskeln“ anbieten, der nur eigene Übungen ohne Haupt- und Hilfsmuskeln zeigt; schreibgeschützte Basisübungen MUST NOT erscheinen, weil der Nutzer ihre Muskeln nicht nachtragen kann. Die Muskelübersicht SHALL unabhängig von Plänen und Trainings die Zeile „Alle Übungen ohne Muskeln“ mit der Anzahl nicht archivierter eigener Übungen ohne Muskeln zeigen. Die Zeile MUST die Übungsverwaltung mit eingeschaltetem Schalter öffnen. Ohne solche Übungen MUST sie „Keine“ zeigen und darf nicht antippbar sein.

#### Scenario: Übung außerhalb der Pläne
- **GIVEN** die eigene Übung „Facepulls“ ohne Muskeln steht in keinem Plan und wurde nie trainiert
- **WHEN** der Nutzer in der Muskelübersicht „Alle Übungen ohne Muskeln“ antippt
- **THEN** öffnet sich die Übungsverwaltung mit „Nur ohne Muskeln“ und listet „Facepulls“

#### Scenario: Filter in der Übungsverwaltung
- **GIVEN** „Schulterdrücken“ hat Brust als Hauptmuskel, „Facepulls“ hat keine Muskeln
- **WHEN** der Nutzer „Nur ohne Muskeln“ einschaltet
- **THEN** erscheint „Facepulls“ und „Schulterdrücken“ nicht
