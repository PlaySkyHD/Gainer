# overview Specification

## Purpose
Der erste Tab „Übersicht“ zeigt zuerst den gewählten Tag mit Plan, Training, Ernährung, Gewicht, Trainingsübersicht und Check-in und darunter den Monatskalender. Er arbeitet aus lokalen Daten und offline.

## Requirements

### Requirement: Übersicht mit dem Tag zuerst

Der erste Tab SHALL „Übersicht“ heißen und beim App-Start mit dem heutigen Tag ausgewählt sein. Die Seite SHALL zuerst die Karten des gewählten Tages zeigen, in der Reihenfolge Plan oder Training, Ernährung, Gewicht, Trainingsübersicht, Check-in. Der Monatskalender SHALL als letzte Karte darunter stehen.

#### Scenario: App öffnen
- **GIVEN** heute ist Samstag, der 24. Oktober
- **WHEN** der Nutzer die App öffnet
- **THEN** ist der Tab „Übersicht“ aktiv, oben steht „Heute“ und die Ernährung von heute steht vor dem Monatskalender

#### Scenario: Tag im Kalender wählen
- **GIVEN** der Nutzer hat bis zum Monatskalender gescrollt
- **WHEN** er den 18. Oktober antippt
- **THEN** scrollt die Seite nach oben und zeigt die Werte des 18. Oktober

### Requirement: Tageswechsel oben

Oben links SHALL die Tages-Pille stehen. Die Pfeile SHALL einen Tag zurück oder vor wechseln, auch über Monatsgrenzen. Ein Tipp auf den Text SHALL zum Monatskalender scrollen. Ist ein anderer Tag als heute gewählt, SHALL „Zu heute“ neben der Datumsüberschrift zurück zum heutigen Tag führen.

#### Scenario: Ein Tag zurück
- **GIVEN** die Übersicht zeigt den 1. November
- **WHEN** der Nutzer den linken Pfeil antippt
- **THEN** zeigt sie den 31. Oktober, und der Kalender unten zeigt Oktober

#### Scenario: Zurück zu heute
- **GIVEN** die Übersicht zeigt den 18. Oktober
- **WHEN** der Nutzer „Zu heute“ antippt
- **THEN** zeigt sie den heutigen Tag, und der Button verschwindet

### Requirement: Monatskalender

Der Monatskalender SHALL mit Montag beginnen, deutsche Monats- und Wochentagsnamen nutzen, heute hervorheben und den gewählten Tag markieren. Wischen nach links oder rechts und die Pfeile „Vorheriger Monat“ und „Nächster Monat“ MUST den Monat wechseln. Danach ist heute gewählt, wenn heute im Monat liegt, sonst der Erste des Monats.

#### Scenario: Monat wechseln
- **GIVEN** heute ist der 24. Oktober und der Kalender zeigt Oktober
- **WHEN** der Nutzer nach links wischt
- **THEN** zeigt der Kalender November und der 1. November ist gewählt

### Requirement: Tagesmarkierungen

Jeder Tag im Raster SHALL höchstens diese Markierungen in fester Reihenfolge zeigen: Krafttraining beendet, Cardio beendet, Check-in vorhanden, geplantes Training (nur heute oder künftig und noch nicht erledigt), verpasstes Training. Ernährung MUST NOT eine Markierung erzeugen.

#### Scenario: Markierungen
- **GIVEN** gestern wurde Push beendet und ein Check-in erfasst, morgen ist Pull geplant
- **WHEN** der Nutzer den Monat ansieht
- **THEN** zeigt gestern die Markierungen Krafttraining und Check-in und morgen die Markierung für geplant

### Requirement: Karten des Tages

Eine Karte MUST nur erscheinen, wenn es für den Tag Inhalt gibt. Gewicht und Trainingsübersicht erscheinen nur für heute. Hat ein vergangener Tag keinen Inhalt, zeigt die Ansicht „Keine Einträge“, ein künftiger Tag ohne Plan „Nichts geplant“. Zahlen MUST deutsch formatiert und beschriftet sein.

#### Scenario: Leerer Tag
- **GIVEN** am 3. wurde nichts erfasst und kein Rhythmus galt
- **WHEN** der Nutzer den 3. wählt
- **THEN** zeigt die Übersicht „Keine Einträge“

#### Scenario: Vergangener Tag ohne Gewichtskarte
- **GIVEN** am 14. gibt es einen Check-in mit 80,4 kg
- **WHEN** der Nutzer den 14. wählt
- **THEN** zeigt die Check-in-Karte 80,4 kg, und es gibt keine Gewichtskarte mit Verlauf und keine Trainingsübersicht

### Requirement: Plan-Karte

Die Plan-Karte SHALL das geplante Training mit Status zeigen (geplant, erledigt, verpasst, verschoben, übersprungen, pausiert, Ruhetag, „Stattdessen: …“) und die zulässigen Tagesaktionen aus `training-schedule` anbieten. Für heute zeigt sie die Karte „Heute: <Plan>“ aus `training-schedule`. „Starten“ MUST nur am heutigen Tag erscheinen. Ohne Rhythmus MUST die Karte von heute auf „Rhythmus einrichten“ verweisen.

#### Scenario: Künftiger Tag
- **GIVEN** am Freitag ist Beine geplant
- **WHEN** der Nutzer Freitag antippt
- **THEN** zeigt nur die Plan-Karte „Beine“ mit „Verschieben…“ und „Überspringen“, aber ohne „Starten“

### Requirement: Einträge des Tages

Die Karte Training SHALL beendete Krafttrainings mit Titel, Dauer und Volumen sowie Cardio-Einheiten zeigen; ein Tipp öffnet die Zusammenfassung bzw. Detailansicht. Die Karte Check-in SHALL Gewicht, Schritte, Schlaf, Ruhepuls und HRV des Tages zeigen, soweit vorhanden; ein Tipp öffnet den Tab „Check-in“.

#### Scenario: Vergangener Tag
- **GIVEN** am 14. wurde Pull beendet
- **WHEN** der Nutzer den 14. wählt
- **THEN** zeigt die Plan-Karte Pull als erledigt und die Karte Training das Training mit Dauer und Volumen

### Requirement: Ernährungskarte

Die Ernährungskarte SHALL die Kalorien des Tages aus den lokalen Ernährungsdaten zeigen: einen offenen Ring mit den übrigen oder überschrittenen Kalorien, links „Gegessen“ und rechts „Ziel“. Darunter stehen Balken für Kohlenhydrate, Eiweiß und Fett und eine eigene Zeile für Ballaststoffe und Salz. Ohne Ziel steht nur „Gegessen“ im Ring. Die Karte MUST keinen Durchschnitt über mehrere Tage zeigen. Ein Tipp öffnet den Tab „Essen“ für diesen Tag.

#### Scenario: Teil des Ziels gegessen
- **GIVEN** am 14. wurden 2.350 kcal bei einem Ziel von 2.600 kcal erfasst
- **WHEN** der Nutzer den 14. wählt
- **THEN** zeigt die Karte „Gegessen“ 2.350 kcal, „Ziel“ 2.600 kcal und im Ring 250 kcal übrig

#### Scenario: Zurück aus dem Ernährungs-Tab
- **GIVEN** die Karte zeigt für heute 100 kcal gegessen
- **WHEN** der Nutzer im Tab „Essen“ Essen hinzufügt und zur Übersicht zurückkehrt
- **THEN** zeigt die Karte die neue Summe, ohne dass eine Verbindung nötig ist

### Requirement: Farbige Makros

Kohlenhydrate, Eiweiß und Fett SHALL auf der Ernährungskarte der Übersicht und auf der Tageskarte im Tab „Essen“ je eine eigene Farbe für Punkt und Balken haben. Werte und Namen MUST in Textfarben stehen. Über dem Ziel SHALL der Balken die Warnfarbe zeigen. Ballaststoffe und Salz SHALL in einer eigenen, zentrierten Zeile stehen.

#### Scenario: Makros unterscheiden
- **GIVEN** ein Tag mit 51 g Kohlenhydraten, 66 g Eiweiß und 29 g Fett
- **WHEN** der Nutzer die Ernährungskarte ansieht
- **THEN** hat jede Makrospalte einen farbigen Punkt und Balken in ihrer Farbe, und die Werte stehen in Textfarbe

#### Scenario: Über dem Ziel
- **GIVEN** Fett 95 g bei einem Ziel von 80 g
- **WHEN** die Karte angezeigt wird
- **THEN** ist der Fett-Balken voll und in Warnfarbe

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

### Requirement: Trainingsübersicht

Die Trainingsübersicht für heute SHALL die Zahl der Trainings der letzten 7 Tage und das Volumen der letzten 30 Tage aus der Dashboard-Auswertung zeigen. Ein Tipp öffnet den Trainings-Tab. Ohne Training steht „Noch kein Training diese Woche“.

#### Scenario: Trainingskarte
- **GIVEN** 4 Trainings in 7 Tagen
- **WHEN** der Nutzer die Übersicht für heute öffnet
- **THEN** zeigt die Karte „4 Trainings in 7 Tagen“ und das Volumen der letzten 30 Tage

### Requirement: Rhythmus aus der Übersicht

Die Toolbar der Übersicht SHALL einen Zugang zum Rhythmus-Editor bieten.

#### Scenario: Kein Rhythmus
- **GIVEN** der Nutzer hat keinen Rhythmus
- **WHEN** er die Übersicht öffnet
- **THEN** zeigt die Plan-Karte „Rhythmus einrichten“ und keine Tage haben die Markierung für geplant

### Requirement: Offline und Aktualität

Die Karten des Tages und der Monatskalender MUST aus lokalen Daten berechnet werden und offline funktionieren; Gewicht und Trainingsübersicht zeigen bei fehlender Verbindung die zuletzt gespeicherten Werte mit Hinweis. Nach einer Änderung in einem anderen Tab, etwa einem beendeten Training oder einer erfassten Mahlzeit, oder nach einem Sync MUST er beim nächsten Anzeigen den neuen Stand zeigen.

#### Scenario: Training beendet
- **GIVEN** heute ist Push geplant
- **WHEN** der Nutzer im Trainings-Tab ein Push-Training beendet und zur Übersicht wechselt
- **THEN** zeigt heute Push als erledigt und die Markierung für Krafttraining

### Requirement: Schritte von heute live

Die Übersicht SHALL für heute die Schrittzahl aus Apple Health zeigen und sie neu lesen, wenn die Übersicht sichtbar wird, die App zurückkommt oder der Nutzer herunterzieht. Der Live-Wert SHALL den gespeicherten Wert des heutigen Check-ins ersetzen. Gibt es heute keinen Check-in, SHALL die Check-in-Karte nur die Schritte zeigen. Das Lesen MUST NOT einen Berechtigungsdialog öffnen.

#### Scenario: Morgens eingecheckt, mittags geöffnet
- **GIVEN** der heutige Check-in hat um 7 Uhr 1.200 Schritte gespeichert und Apple Health meldet jetzt 8.450
- **WHEN** der Nutzer die Übersicht öffnet
- **THEN** zeigt die Check-in-Karte „Schritte 8.450“

#### Scenario: Noch kein Check-in heute
- **GIVEN** es gibt heute keinen Check-in und Apple Health meldet 3.100 Schritte
- **WHEN** die Übersicht lädt
- **THEN** zeigt die Check-in-Karte nur „Schritte 3.100“

#### Scenario: Kein Zugriff
- **GIVEN** Apple Health liefert keine Schritte
- **WHEN** die Übersicht lädt
- **THEN** bleibt der gespeicherte Wert stehen, und es erscheint kein Dialog

### Requirement: Vergangene Tage nachziehen

Beim selben Anlass SHALL die App für Check-ins der letzten 7 Tage ohne heute die Tagessumme aus Apple Health lesen. Ist sie größer als 0 und weicht sie vom gespeicherten Wert ab, SHALL sie nur die Schritte des Check-ins aktualisieren und synchronisieren; alle anderen Werte MUST unverändert bleiben. Tage ohne Check-in MUST NOT angelegt werden.

#### Scenario: Gestern nachgezogen
- **GIVEN** der Check-in von gestern hat 1.200 Schritte und Apple Health meldet für gestern 11.800
- **WHEN** die Übersicht heute lädt
- **THEN** speichert der Check-in von gestern 11.800 Schritte mit unverändertem Gewicht und Schlaf, und eine Sync-Änderung ist vorgemerkt

#### Scenario: Unverändert
- **GIVEN** der gespeicherte Wert entspricht Apple Health
- **WHEN** die Übersicht lädt
- **THEN** entsteht keine Sync-Änderung
