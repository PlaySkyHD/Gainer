# training-schedule Specification

## Purpose
Ein datumsgebundener Trainingsrhythmus (Zyklus oder feste Wochentage) bestimmt, welcher Plan an welchem Tag ansteht. Tagesaktionen verschieben, überspringen oder holen Trainings nach.

## Requirements

### Requirement: Rhythmus anlegen

Der Nutzer SHALL genau einen Trainingsrhythmus anlegen, ändern und löschen können. Ein Rhythmus MUST den Modus Zyklus oder Feste Tage haben. Jeder Slot ist ein aktiver Plan oder ein Ruhetag, und mindestens ein Slot MUST ein Plan sein.

#### Scenario: Nur Ruhetage
- **GIVEN** der Rhythmus-Editor
- **WHEN** der Nutzer einen Zyklus nur aus Ruhetagen speichern will
- **THEN** ist „Speichern“ deaktiviert und der Editor erklärt, dass mindestens ein Plan nötig ist

### Requirement: Modus Zyklus

Ein Zyklus MUST 1 bis 28 Slots in fester Reihenfolge haben. Beim Speichern SHALL der Nutzer wählen, welcher Slot heute ist.

#### Scenario: Zyklus anlegen
- **GIVEN** die aktiven Pläne „Push“, „Pull“ und „Beine“
- **WHEN** der Nutzer den Zyklus `Push · Pull · Beine · Ruhe` speichert und „Push“ als heutigen Slot wählt
- **THEN** zeigt die Vorschau ab heute Push, Pull, Beine, Ruhetag, Push, … an aufeinanderfolgenden Tagen

### Requirement: Modus Feste Tage

Feste Tage MUST genau sieben Slots von Montag bis Sonntag haben.

#### Scenario: Feste Tage anlegen
- **GIVEN** heute ist Mittwoch
- **WHEN** der Nutzer Mo Push, Di Pull, Mi Beine, Do Ruhe, Fr Oberkörper, Sa Unterkörper, So Ruhe speichert
- **THEN** ist heute Beine geplant und am kommenden Montag Push

### Requirement: Gültig ab

Jede Änderung an Modus oder Slots MUST das Gültig-ab-Datum auf den heutigen lokalen Tag setzen und alle Verschiebungen und Ausnahmen verwerfen.

#### Scenario: Rhythmus geändert
- **GIVEN** gestern war Push geplant und wurde verpasst, morgen wurde übersprungen
- **WHEN** der Nutzer heute die Slots ändert und speichert
- **THEN** zeigt gestern kein verpasstes Training und morgen gilt der neue Rhythmus ohne Überspringen

### Requirement: Datumsbezogene Vorschau

Das System SHALL für jeden lokalen Tag ab dem Gültig-ab-Datum bestimmen, welcher Plan oder Ruhetag vorgesehen ist. Im Zyklus ergibt sich der Slot aus dem Abstand zum Ankertag abzüglich aller wirksamen Verschiebungen, modulo Zykluslänge. Bei festen Tagen ergibt er sich aus dem Wochentag. Ein archivierter Plan in einem Slot MUST als Ruhetag behandelt werden, und der Editor weist darauf hin. Vor dem Gültig-ab-Datum MUST das System keine geplanten oder verpassten Trainings anzeigen.

#### Scenario: Zyklus von 8 Tagen über Wochengrenzen
- **GIVEN** der Zyklus `Push · Pull · Beine · Ruhe · Push · Pull · Beine · Ruhe` beginnt an einem Montag mit Push
- **WHEN** die Vorschau den Dienstag der Folgewoche berechnet
- **THEN** ist dort Push geplant, also einen Wochentag später als in der ersten Woche

#### Scenario: Plan archiviert
- **GIVEN** „Beine“ steht im Rhythmus und wird archiviert
- **WHEN** die Vorschau den Tag mit dem Beine-Slot berechnet
- **THEN** ist der Tag ein Ruhetag und der Rhythmus-Editor markiert den Slot als „Plan archiviert“

### Requirement: Anderes Training ändert den Rhythmus nicht

Ein beendetes Training MUST die Vorschau nicht verändern, auch wenn es aus einem anderen Plan stammt als vorgesehen.

#### Scenario: Beine statt Push
- **GIVEN** heute ist Push geplant und morgen Pull
- **WHEN** der Nutzer heute ein Training aus „Beine“ beendet
- **THEN** bleibt morgen Pull geplant

### Requirement: Rhythmus verschieben

Im Modus Zyklus SHALL der Nutzer ein geplantes Training von heute oder einem späteren Tag um 1 oder 2 Tage verschieben können, sodass dieses und alle folgenden Trainings entsprechend später liegen. Die frei werdenden Tage MUST als „pausiert“ gelten. Im Modus Feste Tage MUST diese Aktion fehlen.

#### Scenario: Um einen Tag verschieben
- **GIVEN** der Zyklus `Push · Pull · Beine · Ruhe`, heute ist Push geplant
- **WHEN** der Nutzer „Rhythmus verschieben → 1 Tag“ wählt
- **THEN** ist heute pausiert, morgen Push, übermorgen Pull, danach Beine und dann ein Ruhetag

### Requirement: Einzelnes Training verschieben oder überspringen

In beiden Modi SHALL der Nutzer ein geplantes Training von heute oder einem späteren Tag nur für sich auf einen der beiden Folgetage verschieben oder überspringen können. Alle anderen Tage MUST unverändert bleiben. Ein Tag kann dadurch mehrere geplante Trainings haben. Eine Ausnahme gilt nur, solange an ihrem Datum noch derselbe Plan vorgesehen ist. Ändert eine spätere Verschiebung des Rhythmus das, ist die Ausnahme wirkungslos.

#### Scenario: Nur dieses auf morgen
- **GIVEN** feste Tage mit Mo Push, Di Pull, heute ist Montag
- **WHEN** der Nutzer Push auf morgen verschiebt
- **THEN** zeigt Montag „Verschoben auf Di“ und Dienstag hat Push und Pull geplant

#### Scenario: Überspringen
- **GIVEN** der Zyklus `Push · Pull · Beine · Ruhe`, heute ist Pull geplant
- **WHEN** der Nutzer Pull überspringt
- **THEN** zeigt heute „Übersprungen“ und morgen bleibt Beine geplant

### Requirement: Verpasste Trainings

Ein geplantes Training an einem vergangenen Tag ab dem Gültig-ab-Datum MUST als „verpasst“ gelten, wenn an diesem Tag kein Training beendet wurde. Hat der Nutzer stattdessen ein anderes Training beendet, MUST der Tag „Stattdessen: <Titel>“ zeigen und nicht als verpasst gelten.

#### Scenario: Anderes Training statt Plan
- **GIVEN** gestern war Push geplant
- **WHEN** der Nutzer gestern ein Training „Beine“ beendet hat
- **THEN** zeigt gestern „Stattdessen: Beine“ und keine Markierung für verpasst

### Requirement: Verpasstes nachholen

Für ein verpasstes Training, das höchstens 7 Tage zurückliegt, SHALL der Nutzer „Heute nachholen“ wählen können; das verschiebt nur dieses Training auf heute. Im Modus Zyklus SHALL zusätzlich „Ab heute weiter“ angeboten werden; das verschiebt den Rhythmus ab dem verpassten Tag, sodass das Training heute liegt.

#### Scenario: Nachholen bei festen Tagen
- **GIVEN** feste Tage mit Mo Push, heute ist Mittwoch und am Montag wurde nichts trainiert
- **WHEN** der Nutzer bei Montag „Heute nachholen“ wählt
- **THEN** zeigt Montag „Verschoben auf Mi“ und heute ist zusätzlich Push geplant

#### Scenario: Ab heute weiter im Zyklus
- **GIVEN** der Zyklus `Push · Pull · Beine · Ruhe`, vorgestern war Push geplant und wurde verpasst
- **WHEN** der Nutzer bei vorgestern „Ab heute weiter“ wählt
- **THEN** ist heute Push, morgen Pull geplant und die beiden Tage davor sind pausiert

#### Scenario: Zu alt zum Nachholen
- **GIVEN** ein verpasstes Training vor 9 Tagen
- **WHEN** der Nutzer den Tag öffnet
- **THEN** wird es als verpasst angezeigt, aber ohne Aktion zum Nachholen

### Requirement: Erfüllung

Ein geplantes Training MUST als erledigt gelten, wenn am selben lokalen Tag ein beendetes, nicht gelöschtes Training aus genau diesem Plan gestartet wurde. Gelöschte Trainings MUST NOT zählen. Cardio-Einheiten erfüllen kein geplantes Krafttraining.

#### Scenario: Training gelöscht
- **GIVEN** gestern war Pull geplant und ein Pull-Training wurde beendet
- **WHEN** der Nutzer dieses Training löscht
- **THEN** gilt Pull gestern als verpasst

### Requirement: Ausnahme aufheben

Der Nutzer SHALL eine Verschiebung oder ein Überspringen aufheben können, solange der betroffene Tag heute oder später ist. Danach MUST die Vorschau wieder dem Rhythmus ohne diese Ausnahme entsprechen.

#### Scenario: Überspringen aufheben
- **GIVEN** heute wurde Pull übersprungen
- **WHEN** der Nutzer „Aufheben“ wählt
- **THEN** ist heute wieder Pull geplant

### Requirement: Heutiges Training im Trainings-Tab

Der Trainings-Tab SHALL eine Karte für heute zeigen:
- Ist ein Training geplant und noch nicht erledigt: „Heute: <Plan>“ mit „Starten“.
- Ist das Training erledigt: „Heute erledigt: <Plan>“.
- Ist ein Ruhetag oder pausiert: „Ruhetag“ mit dem nächsten geplanten Training und dessen Tag.
- Gibt es keinen Rhythmus: „Rhythmus einrichten“.

„Starten“ MUST das Training aus dem Plan genauso starten wie aus der Planliste.

#### Scenario: Ruhetag
- **GIVEN** heute ist Ruhetag und Donnerstag ist Pull geplant
- **WHEN** der Nutzer den Trainings-Tab öffnet
- **THEN** zeigt die Karte „Ruhetag · Nächstes: Pull am Do“

### Requirement: Speichern und Synchronisation

Der Rhythmus MUST offline geändert werden können und als eine Ressource mit Versionsprüfung über den Sync-Vertrag gespeichert werden. Jede Mutation überträgt den vollständigen Stand. Eine wiederholt gesendete Mutation mit derselben Mutation-ID MUST NOT doppelt angewendet werden. Hängt eine Mutation an einem noch nicht gesendeten neuen Plan, MUST der Client den Plan zuerst senden.

#### Scenario: Offline geändert
- **GIVEN** das Gerät ist offline
- **WHEN** der Nutzer heute überspringt und danach morgen verschiebt
- **THEN** zeigt die App beide Änderungen sofort, die Outbox enthält einen zusammengefassten Stand, und nach Wiederverbindung hat der Server genau diesen Stand

#### Scenario: Veralteter Stand
- **GIVEN** der Server hat den Rhythmus in Version 4
- **WHEN** eine Mutation mit Basisversion 3 eintrifft
- **THEN** meldet der Server einen Konflikt und die App bietet die bestehende Konfliktauflösung an

### Requirement: Serverseitige Prüfung

Der Server MUST eine Mutation ablehnen, wenn ein Slot einen Plan referenziert, der nicht dem angemeldeten Nutzer gehört oder nicht existiert. Dasselbe gilt, wenn die Slot-Regeln verletzt sind oder mehr als 1000 Verschiebungen und Ausnahmen zusammen gespeichert würden.

#### Scenario: Fremder Plan
- **GIVEN** Nutzer A und Nutzer B mit je eigenen Plänen
- **WHEN** Nutzer A einen Rhythmus mit einer Plan-ID von Nutzer B speichert
- **THEN** antwortet der Server mit einem Validierungsfehler und speichert nichts

### Requirement: Rotation entfällt

Die Plan-Rotation MUST vollständig entfernt sein. Mutationen vom Typ `SaveWorkoutRotation` MUST der Server als unbekannte Operation ablehnen. Beim Upgrade MUST die App lokale Rotationsdaten und zugehörige Outbox-Einträge verwerfen, ohne andere Einträge zu verändern.

#### Scenario: Upgrade mit offener Rotations-Mutation
- **GIVEN** auf dem Gerät liegt eine nicht gesendete Rotations-Mutation und eine nicht gesendete Workout-Mutation
- **WHEN** die neue App-Version startet
- **THEN** ist die Rotations-Mutation entfernt und die Workout-Mutation wird normal gesendet
