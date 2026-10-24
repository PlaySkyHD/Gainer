# today-overview

## ADDED Requirements

### Requirement: Ernährungskarte zeigt den heutigen Tag

Die Ernährungskarte auf „Heute“ SHALL die Kalorien des lokalen heutigen Kalendertags aus den lokalen Ernährungsdaten zeigen, beschriftet mit „kcal heute“, und darunter das Protein von heute, sofern bekannt. Sie MUST ohne Verbindung funktionieren und MUST keinen Durchschnitt über mehrere Tage zeigen.

#### Scenario: Einträge vorhanden
- **GIVEN** heute sind 1.280 kcal und 42 g Protein erfasst
- **WHEN** der Nutzer „Heute“ öffnet
- **THEN** zeigt die Karte „1.280 kcal heute“ und „Protein 42 g“

#### Scenario: Heute noch nichts erfasst
- **GIVEN** gestern war etwas erfasst, heute nicht
- **WHEN** der Nutzer „Heute“ öffnet
- **THEN** zeigt die Karte „0 kcal heute“ und keinen Durchschnitt

#### Scenario: Zurück aus dem Ernährungs-Tab
- **GIVEN** die Karte zeigt „100 kcal heute“
- **WHEN** der Nutzer im Ernährungs-Tab Essen hinzufügt und zu „Heute“ zurückkehrt
- **THEN** zeigt die Karte die neue Summe, ohne dass eine Verbindung nötig ist

### Requirement: Gewichtskarte zeigt das Alter des Eintrags

Die Gewichtskarte SHALL unter dem letzten Gewicht das Alter des Eintrags in Kalendertagen gegenüber dem lokalen heutigen Datum zeigen. 0 Tage: „Heute“; 1 Tag: „Gestern“ (beide in Sekundärfarbe); 2 bis 6 Tage: „vor N Tagen“ in Warnfarbe; ab 7 Tagen: „vor N Tagen“ in Fehlerfarbe. Das Label MUST für Screenreader als „Letztes Gewicht: …“ erreichbar sein.

#### Scenario: Gewicht von heute
- **GIVEN** der letzte Eintrag ist von heute
- **WHEN** die Karte erscheint
- **THEN** steht „Heute“ in Sekundärfarbe darunter

#### Scenario: Gewicht von gestern
- **GIVEN** der letzte Eintrag ist von gestern
- **WHEN** die Karte erscheint
- **THEN** steht „Gestern“ in Sekundärfarbe darunter

#### Scenario: Gewicht von vor 2 bis 6 Tagen
- **GIVEN** der letzte Eintrag ist 2 Tage alt (oder 6 Tage alt)
- **WHEN** die Karte erscheint
- **THEN** steht „vor 2 Tagen“ (bzw. „vor 6 Tagen“) in Warnfarbe darunter

#### Scenario: Gewicht von vor 7 Tagen oder älter
- **GIVEN** der letzte Eintrag ist 7 Tage alt
- **WHEN** die Karte erscheint
- **THEN** steht „vor 7 Tagen“ in Fehlerfarbe darunter

### Requirement: Trainingskarte bleibt unverändert

Die Trainingskarte auf „Heute“ SHALL unverändert bleiben.

#### Scenario: Trainingskarte
- **GIVEN** 4 Trainings in 7 Tagen
- **WHEN** der Nutzer „Heute“ öffnet
- **THEN** zeigt die Karte wie bisher „4 Trainings in 7 Tagen“ und das Volumen
