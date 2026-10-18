# cardio-insights

## ADDED Requirements

### Requirement: Live Activity während Cardio

Während einer laufenden Cardio-Einheit SHALL die App eine Live Activity mit Puls, Zonenstatus, Zielbereich und Dauer zeigen, sofern Live Activities erlaubt sind. Sie MUST bei gesperrtem Display aktualisiert werden und mit dem Beenden der Einheit enden.

#### Scenario: Gesperrtes Display
- **GIVEN** eine laufende Einheit mit Zielbereich 125–140 und gesperrtem iPhone
- **WHEN** der Puls von 130 auf 145 steigt
- **THEN** zeigt die Live Activity 145 bpm und „Zu hoch“ in Warnfarbe

#### Scenario: Live Activities aus
- **GIVEN** Live Activities sind in den iOS-Einstellungen aus
- **WHEN** der Nutzer eine Einheit startet
- **THEN** läuft die Einheit mit Alarm normal, ohne Live Activity und ohne Fehlermeldung

#### Scenario: Beenden
- **GIVEN** eine laufende Einheit mit Live Activity
- **WHEN** der Nutzer „Beenden“ tippt
- **THEN** verschwindet die Live Activity

### Requirement: Export nach Apple Health

Der Nutzer SHALL eine beendete Cardio-Einheit nach Apple Health sichern können: als Indoor-Radtraining mit Pulsproben und, falls vorhanden, Distanz und kcal. Ein erneuter Export derselben Version MUST ohne Dublette mit „bereits vorhanden“ enden. Ohne Schreibrecht MUST die App den Grund zeigen.

#### Scenario: Erster Export
- **GIVEN** eine beendete Einheit mit 360 Pulswerten
- **WHEN** der Nutzer „In Apple Health sichern“ tippt und erlaubt
- **THEN** enthält Apple Health ein Indoor-Radtraining mit Pulsproben und die Detailansicht zeigt „In Apple Health gesichert“

#### Scenario: Doppelt tippen
- **GIVEN** eine bereits exportierte Einheit
- **WHEN** der Export erneut läuft
- **THEN** entsteht kein zweites Workout

### Requirement: Zonen-Empfehlung

Hat der Nutzer Maximalpuls oder Alter angegeben, SHALL die App die Zonen 1–5 nach der festgelegten Formel berechnen und als Auswahl beim Festlegen des Zielbereichs anbieten. Ohne diese Angaben MUST die Auswahl fehlen und ein Hinweis auf die Einstellung erscheinen.

#### Scenario: Zone 2 aus Maximalpuls
- **GIVEN** Maximalpuls 190, kein Ruhepuls
- **WHEN** der Nutzer im Start-Sheet „Zone 2“ tippt
- **THEN** ist der Zielbereich 114–133 bpm

#### Scenario: Karvonen
- **GIVEN** Maximalpuls 190 und Ruhepuls 60
- **WHEN** die Zonen berechnet werden
- **THEN** ist Zone 2 = 138–151 bpm

#### Scenario: Alter statt Maximalpuls
- **GIVEN** Alter 30, kein Maximalpuls
- **WHEN** die Zonen berechnet werden
- **THEN** gilt HFmax 187 und Zone 2 = 112–131 bpm
