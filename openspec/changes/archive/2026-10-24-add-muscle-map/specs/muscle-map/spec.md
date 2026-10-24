# muscle-map

## ADDED Requirements

### Requirement: Muskeln einer Übung

Jede Übung SHALL bis zu 3 Hauptmuskeln und bis zu 6 Hilfsmuskeln aus einer festen Liste von 17 Regionen haben können. Ein Muskel MUST NOT gleichzeitig Haupt- und Hilfsmuskel derselben Übung sein. Eigene Übungen SHALL im Übungseditor bearbeitbar sein, Basisübungen MUST ihre Katalogwerte nur anzeigen. Das Backend MUST unbekannte Schlüssel, Wiederholungen und Überschneidungen ablehnen.

#### Scenario: Muskeln wählen
- **GIVEN** eine eigene Übung „Schrägbankdrücken“ ohne Muskeln
- **WHEN** der Nutzer Brust als Hauptmuskel sowie Trizeps und vordere Schulter als Hilfsmuskeln wählt und speichert
- **THEN** zeigt der Editor die Brust voll und Trizeps und vordere Schulter halb eingefärbt, und die Werte werden synchronisiert

#### Scenario: Überschneidung gesperrt
- **GIVEN** Brust ist Hauptmuskel
- **WHEN** der Nutzer die Hilfsmuskeln auswählt
- **THEN** ist Brust dort gesperrt und als „Hauptmuskel“ beschriftet

### Requirement: Sätze je Muskel

Die App SHALL je Muskel die Arbeitssätze zählen. Ein Hauptmuskel zählt 1 je Arbeitssatz, ein Hilfsmuskel 0,5. Aufwärmsätze MUST NOT zählen.

#### Scenario: Geplante Sätze
- **GIVEN** ein Plan mit Bankdrücken (Haupt Brust, Hilfs Trizeps) mit 4 Arbeitssätzen und Trizepsdrücken (Haupt Trizeps) mit 3 Arbeitssätzen
- **WHEN** die Muskelübersicht diesen Plan zeigt
- **THEN** stehen bei Brust 4 Sätze und bei Trizeps 5 Sätze

#### Scenario: Trainierte Sätze
- **GIVEN** zwei abgeschlossene Trainings in den letzten 7 Tagen mit je 2 Aufwärm- und 3 Arbeitssätzen Kniebeugen (Haupt Quadrizeps)
- **WHEN** die Übersicht „Trainiert, 7 Tage“ zeigt
- **THEN** stehen bei Quadrizeps 6 Sätze

### Requirement: Muskelübersicht

Die App SHALL eine Körperkarte mit Vorder- und Rückansicht zeigen, deren Farbstufen der Satzzahl je Muskel folgen. Die Übersicht SHALL zwischen „Geplant“ (alle aktiven Pläne oder ein einzelner Plan) und „Trainiert“ (letzte 7 Tage oder Ø pro Woche der letzten 28 Tage) umschalten. Übungen ohne Muskelangabe MUST als Hinweis genannt werden.

#### Scenario: Gesamtbild aller Pläne
- **GIVEN** die aktiven Pläne „Push“ und „Pull“ trainieren keine Beine
- **WHEN** der Nutzer „Geplant, Alle Pläne“ öffnet
- **THEN** sind Quadrizeps, Beinbeuger, Gesäß und Waden grau und stehen mit 0 Sätzen in der Liste

#### Scenario: Ein Plan
- **GIVEN** die Übersicht zeigt alle Pläne
- **WHEN** der Nutzer unter „Plan“ den Plan „Pull“ wählt
- **THEN** zeigt Karte und Liste nur die Sätze aus „Pull“

#### Scenario: Muskel antippen
- **GIVEN** die Übersicht zeigt Brust mit 8 Sätzen
- **WHEN** der Nutzer auf die Brust tippt
- **THEN** listet ein Sheet die beitragenden Übungen mit ihren Sätzen und ob die Brust dort Haupt- oder Hilfsmuskel ist

### Requirement: Muskeln im Plan-Editor

Der Plan-Editor SHALL eine Körperkarte des Plans zeigen, sobald er eine Übung enthält. Sie MUST dem aktuellen, auch ungespeicherten Stand folgen.

#### Scenario: Übung hinzufügen
- **GIVEN** ein Plan mit nur Bankdrücken
- **WHEN** der Nutzer Klimmzüge hinzufügt
- **THEN** färbt die Karte sofort zusätzlich den Latissimus ein

### Requirement: Muskeln nachtragen

Die App SHALL den Übungseditor aus dem Übungsmenü eines Trainings und aus der Liste „Ohne Muskeln“ der Muskelübersicht öffnen. Übungen, die nicht im Katalog bekannt sind, MUST NOT einen Editor anbieten.

#### Scenario: Aus dem Training
- **GIVEN** ein aktives Training mit der eigenen Übung „Schrägbankdrücken“
- **WHEN** der Nutzer im Übungsmenü „Übung bearbeiten“ wählt
- **THEN** öffnet sich der Übungseditor mit dem Abschnitt „Muskeln“

#### Scenario: Aus der Übersicht
- **GIVEN** die Übersicht listet „Curls“ unter „Ohne Muskeln“
- **WHEN** der Nutzer „Curls“ antippt, Bizeps als Hauptmuskel wählt und speichert
- **THEN** fehlt „Curls“ in der Gruppe und die Karte zählt die Sätze beim Bizeps

