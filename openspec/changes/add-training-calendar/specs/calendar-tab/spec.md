# calendar-tab

## ADDED Requirements

### Requirement: Kalender ersetzt Heute

Der erste Tab der Tab-Leiste MUST „Kalender“ heißen, ein Kalender-Symbol tragen und beim App-Start ausgewählt sein. Ausgewählt ist dabei der heutige Tag. Der bisherige Tab „Heute“ MUST entfallen. Die übrigen Tabs bleiben unverändert.

#### Scenario: App-Start
- **GIVEN** ein angemeldeter Nutzer
- **WHEN** die App startet
- **THEN** ist der Tab „Kalender“ aktiv und der heutige Tag ausgewählt

### Requirement: Monatsraster

Der Kalender SHALL ein Monatsraster zeigen, das mit Montag beginnt, deutsche Monats- und Wochentagsnamen nutzt und heute hervorhebt. Wischen nach links oder rechts MUST den Monat wechseln. Der Toolbar-Button „Heute“ MUST zum aktuellen Monat springen und heute auswählen.

#### Scenario: Monat wechseln und zurück
- **GIVEN** der Nutzer hat zwei Monate zurückgewischt
- **WHEN** er „Heute“ tippt
- **THEN** zeigt das Raster den aktuellen Monat und heute ist ausgewählt

### Requirement: Tagesmarkierungen

Jeder Tag im Raster SHALL höchstens diese Markierungen in fester Reihenfolge zeigen: Krafttraining beendet, Cardio beendet, Check-in vorhanden, geplantes Training (nur heute oder künftig und noch nicht erledigt), verpasstes Training. Ernährung MUST NOT eine Markierung erzeugen.

#### Scenario: Markierungen
- **GIVEN** gestern wurde Push beendet und ein Check-in erfasst, morgen ist Pull geplant
- **WHEN** der Nutzer den Monat ansieht
- **THEN** zeigt gestern die Markierungen Krafttraining und Check-in und morgen die Markierung für geplant

### Requirement: Tagesansicht

Unter dem Raster SHALL die Tagesansicht des gewählten Tages stehen, aus gruppierten Karten für Plan, Training, Ernährung und Check-in. Eine Karte MUST nur erscheinen, wenn es Inhalt gibt. Hat ein vergangener Tag keinen Inhalt, zeigt die Ansicht „Keine Einträge“. Zahlen MUST deutsch formatiert und beschriftet sein.

#### Scenario: Leerer Tag
- **GIVEN** am 3. wurde nichts erfasst und kein Rhythmus galt
- **WHEN** der Nutzer den 3. antippt
- **THEN** zeigt die Tagesansicht „Keine Einträge“

### Requirement: Plan-Karte

Die Plan-Karte SHALL das geplante Training mit Status zeigen (geplant, erledigt, verpasst, verschoben, übersprungen, pausiert, Ruhetag, „Stattdessen: …“) und die zulässigen Tagesaktionen aus `training-schedule` anbieten. „Starten“ MUST nur am heutigen Tag erscheinen.

#### Scenario: Künftiger Tag
- **GIVEN** am Freitag ist Beine geplant
- **WHEN** der Nutzer Freitag antippt
- **THEN** zeigt nur die Plan-Karte „Beine“ mit „Verschieben…“ und „Überspringen“, aber ohne „Starten“

### Requirement: Einträge des Tages

Die Karte Training SHALL beendete Krafttrainings mit Titel, Dauer und Volumen sowie Cardio-Einheiten zeigen; ein Tipp öffnet die bestehende Zusammenfassung bzw. Detailansicht. Die Karte Ernährung SHALL Kalorien mit Ziel und Protein zeigen; ein Tipp öffnet den Tab „Essen“ für diesen Tag. Die Karte Check-in SHALL die Werte des Tages zeigen; ein Tipp öffnet den Tab „Check-in“.

#### Scenario: Vergangener Tag
- **GIVEN** am 14. wurde Pull beendet und 2.350 kcal bei einem Ziel von 2.600 kcal erfasst
- **WHEN** der Nutzer den 14. antippt
- **THEN** zeigt die Tagesansicht Pull als erledigt, das Training mit Dauer und Volumen sowie „2.350 von 2.600 kcal“

### Requirement: Heute behält die Übersicht

Ist heute ausgewählt, MUST die Tagesansicht zusätzlich die Inhalte des bisherigen Heute-Tabs zeigen: Gewichtsverlauf, Ernährung von heute und die Trainingsübersicht. Sie erscheinen in dieser Reihenfolge nach der Plan-Karte. Inhalte, die schon in einer anderen Karte stehen, MUST NOT doppelt erscheinen.

#### Scenario: Heute
- **GIVEN** heute ist Push geplant und es gibt Gewichtswerte
- **WHEN** der Nutzer den Kalender öffnet
- **THEN** stehen „Heute: Push“ mit „Starten“ und darunter der Gewichtsverlauf

### Requirement: Rhythmus aus dem Kalender

Die Toolbar des Kalenders SHALL einen Zugang zum Rhythmus-Editor bieten. Ohne Rhythmus MUST die Plan-Karte von heute auf „Rhythmus einrichten“ verweisen.

#### Scenario: Kein Rhythmus
- **GIVEN** der Nutzer hat keinen Rhythmus
- **WHEN** er den Kalender öffnet
- **THEN** zeigt die Plan-Karte „Rhythmus einrichten“ und keine Tage haben die Markierung für geplant

### Requirement: Offline und Aktualität

Der Kalender MUST ausschließlich aus lokalen Daten berechnet werden und offline vollständig funktionieren. Nach einer Änderung in einem anderen Tab, etwa einem beendeten Training oder einer erfassten Mahlzeit, oder nach einem Sync MUST er beim nächsten Anzeigen den neuen Stand zeigen.

#### Scenario: Training beendet
- **GIVEN** heute ist Push geplant
- **WHEN** der Nutzer im Trainings-Tab ein Push-Training beendet und zum Kalender wechselt
- **THEN** zeigt heute Push als erledigt und die Markierung für Krafttraining
