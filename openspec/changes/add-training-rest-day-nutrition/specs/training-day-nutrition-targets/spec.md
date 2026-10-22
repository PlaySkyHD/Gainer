# training-day-nutrition-targets

## Purpose

Ernährungsziele sind einfache Ziele für Trainingstage und optional für Ruhetage. Sie lassen sich jederzeit mit Wirkung ab heute ändern. Welche Tagesart gilt, ergibt sich aus Training und Rhythmus, oder der Nutzer legt sie für einen Tag selbst fest.

## ADDED Requirements

### Requirement: Ziele für Trainings- und Ruhetag

Der Tab „Essen“ SHALL einen Bereich „Ziele“ zeigen. Er enthält ein Trainingstag-Ziel, ein optionales Ruhetag-Ziel und eine gemeinsame Salzobergrenze. Beide Ziele haben kcal, Eingabemodus und Makros und MUST gleich validiert werden. Das Ruhetag-Ziel SHALL per Schalter „Eigenes Ziel für Ruhetage“ ein- und ausschaltbar sein. Phasenname, Kategorie, Zeiträume und Phasenliste MUST NOT angezeigt werden.

#### Scenario: Ziele anlegen
- **GIVEN** der Nutzer hat noch keine Ziele
- **WHEN** er „Ziele festlegen“ wählt, als Trainingstag 2.600 kcal mit 180 g Protein, 290 g Kohlenhydraten und 80 g Fett einträgt, den Schalter einschaltet, als Ruhetag 2.200 kcal mit 180 g Protein, 190 g Kohlenhydraten und 80 g Fett einträgt und speichert
- **THEN** zeigt der Bereich „Ziele“ „Trainingstag 2.600 kcal“ und „Ruhetag 2.200 kcal“

#### Scenario: Ungültiges Ruhetag-Ziel
- **GIVEN** der Editor mit eingeschaltetem Ruhetag-Ziel im Prozentmodus
- **WHEN** die Prozente des Ruhetag-Ziels zusammen 90 ergeben
- **THEN** ist „Speichern“ deaktiviert und der Editor nennt den Fehler beim Ruhetag-Ziel

#### Scenario: Ruhetag-Ziel ausschalten
- **GIVEN** Ziele mit Ruhetag-Ziel
- **WHEN** der Nutzer den Schalter ausschaltet und speichert
- **THEN** gilt ab heute an allen Tagen das Trainingstag-Ziel

### Requirement: Änderungen gelten ab heute

Speichert der Nutzer geänderte Ziele, MUST die Änderung ab dem heutigen lokalen Tag gelten. Tage davor MUST weiterhin mit dem Ziel verglichen werden, das an ihnen galt. Mehrere Änderungen am selben Tag MUST zu einem einzigen Ziel für diesen Tag führen, und zwar zum zuletzt gespeicherten. Ziele, die noch aus früheren Zielphasen stammen und erst künftig beginnen würden, MUST beim Speichern verworfen werden.

#### Scenario: Ruhetag-Ziel nachträglich einführen
- **GIVEN** seit 01.10. gilt das Ziel 2.600 kcal ohne Ruhetag-Ziel, heute ist der 22.10., und der 20.10. war ein Ruhetag mit 2.300 kcal
- **WHEN** der Nutzer ein Ruhetag-Ziel von 2.200 kcal einführt und speichert
- **THEN** wird der 20.10. weiterhin mit 2.600 kcal verglichen, und ab dem 22.10. gilt an Ruhetagen 2.200 kcal

#### Scenario: Zweimal am selben Tag geändert
- **GIVEN** der Nutzer hat heute das Trainingstag-Ziel auf 2.500 kcal geändert
- **WHEN** er es heute noch einmal auf 2.550 kcal ändert
- **THEN** gilt ab heute 2.550 kcal, und die Historie enthält für heute genau ein Ziel

#### Scenario: Offline geändert, später synchronisiert
- **GIVEN** das Gerät ist am 22.10. offline, und der Nutzer ändert die Ziele
- **WHEN** das Gerät erst am 24.10. wieder online ist
- **THEN** nimmt der Server die Änderung an, und sie gilt ab dem 22.10.

### Requirement: Unveränderliche Historie auf dem Server

Eine Mutation des Zielplans MUST nur Tage ab dem Beginn ihrer neuesten Version verändern. Davor darf sie lediglich das Ende der Version setzen, die den Vortag abdeckt. Eine gespeicherte Version, die an diesem Tag beginnt, darf geändert werden. Eine, die später beginnt, darf nur entfernt werden, wenn sie noch nicht begonnen hat. Alles andere MUST der Server als Konflikt ablehnen. Offline gemachte Änderungen MUST auch Tage später angenommen werden.

#### Scenario: Abgeschlossene Version ändern
- **GIVEN** eine Version vom 01.10. bis 21.10. und eine offene Version ab 22.10.
- **WHEN** eine Mutation die kcal der Version bis 21.10. ändern will
- **THEN** antwortet der Server mit einem Konflikt und speichert nichts

#### Scenario: Neue Version vor der offenen
- **GIVEN** die offene Version beginnt am 22.10.
- **WHEN** eine Mutation eine neue Version ab 20.10. anlegen will
- **THEN** antwortet der Server mit einem Konflikt und speichert nichts

### Requirement: Tagesart automatisch bestimmen

Die App MUST für jeden lokalen Tag automatisch bestimmen, ob er Trainingstag oder Ruhetag ist:

1. Ein nicht gelöschtes Krafttraining wurde an dem Tag gestartet und beendet: **Trainingstag**.
2. Laut Rhythmus steht ein Training an, das weder verschoben noch übersprungen ist, auch erledigt, verpasst oder hierher verschoben: **Trainingstag**.
3. Sonst, auch ohne Rhythmus: **Ruhetag**.

Cardio MUST NOT die Tagesart beeinflussen.

#### Scenario: Geplantes Training
- **GIVEN** der Rhythmus sieht heute Push vor und es wurde noch nicht trainiert
- **WHEN** die App die Tagesart von heute bestimmt
- **THEN** ist heute ein Trainingstag

#### Scenario: Training an einem Ruhetag
- **GIVEN** laut Rhythmus ist heute Ruhetag
- **WHEN** der Nutzer heute ein Training aus „Beine“ beendet
- **THEN** ist heute ein Trainingstag

#### Scenario: Training verschoben
- **GIVEN** feste Tage mit Mo Push und Di Pull, und Push wurde von Montag auf Dienstag verschoben
- **WHEN** die App Montag und Dienstag bestimmt
- **THEN** ist Montag ein Ruhetag und Dienstag ein Trainingstag

#### Scenario: Verpasstes Training
- **GIVEN** gestern war Pull geplant und es wurde nichts trainiert
- **WHEN** die App die Tagesart von gestern bestimmt
- **THEN** ist gestern ein Trainingstag

#### Scenario: Ohne Rhythmus
- **GIVEN** der Nutzer hat keinen Rhythmus
- **WHEN** die App einen Tag ohne beendetes Krafttraining bestimmt
- **THEN** ist der Tag ein Ruhetag

#### Scenario: Gelöschtes Training
- **GIVEN** laut Rhythmus war gestern Ruhetag und ein dort beendetes Training wurde gelöscht
- **WHEN** die App die Tagesart von gestern bestimmt
- **THEN** ist gestern ein Ruhetag

### Requirement: Tagesart manuell festlegen

Der Nutzer SHALL für jeden Tag, auch vergangene und künftige, festlegen können, dass er als Trainingstag oder Ruhetag zählt. Die Festlegung MUST Vorrang vor der automatischen Tagesart haben und sich mit „Automatisch“ aufheben lassen. Sie MUST NOT den Rhythmus oder den Status geplanter Trainings ändern. Gilt für den Tag kein Ruhetag-Ziel, MUST die Auswahl ausgeblendet sein. Eine bestehende Festlegung bleibt dann gespeichert, wirkt aber nicht.

#### Scenario: Verpasstes Training als Ruhetag zählen
- **GIVEN** gestern war Pull geplant und wurde verpasst, und gestern galt ein Ruhetag-Ziel
- **WHEN** der Nutzer für gestern „Zählt als: Ruhetag“ wählt
- **THEN** wird gestern mit dem Ruhetag-Ziel verglichen, und im Kalender bleibt Pull als verpasst markiert

#### Scenario: Festlegung aufheben
- **GIVEN** für heute ist „Ruhetag“ festgelegt und laut Rhythmus steht Push an
- **WHEN** der Nutzer „Automatisch“ wählt
- **THEN** zählt heute wieder als Trainingstag

#### Scenario: Festlegung an einem leeren Tag
- **GIVEN** für morgen gibt es noch keine Einträge
- **WHEN** der Nutzer für morgen „Ruhetag“ festlegt
- **THEN** bleibt die Festlegung gespeichert, und morgen zeigt die Tageskarte das Ruhetag-Ziel ohne Einträge

#### Scenario: Ohne Ruhetag-Ziel
- **GIVEN** für den Tag gilt kein Ruhetag-Ziel
- **WHEN** der Nutzer den Tag im Tab „Essen“ öffnet
- **THEN** gibt es keine Auswahl „Zählt als“

### Requirement: Ziel eines Tages

Das Ziel eines Tages MUST sich aus den an diesem Tag gültigen Zielen ergeben. Gibt es ein Ruhetag-Ziel und zählt der Tag als Ruhetag, gilt das Ruhetag-Ziel. Sonst gilt das Trainingstag-Ziel. Tageskarte und Kalender SHALL neben dem Ziel die Tagesart zeigen, „Trainingstag“ oder „Ruhetag“, mit dem Zusatz „manuell“ bei einer Festlegung. Ohne Ruhetag-Ziel MUST keine Tagesart angezeigt werden.

#### Scenario: Ruhetag in der Tageskarte
- **GIVEN** Trainingstag 2.600 kcal und Ruhetag 2.200 kcal, heute ist laut Rhythmus Ruhetag, und erfasst sind 1.800 kcal
- **WHEN** der Nutzer den Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte „Ruhetag“ und „1.800 von 2.200 kcal“ mit 400 kcal verbleibend

#### Scenario: Ohne Ziele
- **GIVEN** der Nutzer hat keine Ziele
- **WHEN** er den Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte die aufgenommenen Werte ohne Fortschrittsbalken und bietet „Ziele festlegen“ an

### Requirement: Kalender und Durchschnitte

Die Ernährungskarte der Kalender-Tagesansicht SHALL das Ziel des Tages und die Tagesart zeigen. Sie SHALL dieselbe Auswahl „Zählt als“ anbieten wie der Tab „Essen“. Der Zielvergleich der Durchschnitte MUST pro Tag das Ziel des Tages verwenden. Das Monatsraster MUST NOT eine neue Markierung für die Tagesart bekommen.

#### Scenario: Durchschnitt über Trainings- und Ruhetage
- **GIVEN** Training 2.600 kcal und Ruhe 2.200 kcal; erfasst sind 2 Trainingstage mit je 2.600 kcal und 1 Ruhetag mit 2.600 kcal
- **WHEN** der Nutzer die Durchschnitte über diese 3 Tage ansieht
- **THEN** ist Ø Ziel 2.466,67 kcal (angezeigt gerundet „2.467 kcal“), und 2 von 3 Tagen liegen im Zielbereich, weil 2.600 beim Ruhetag-Ziel 2.200 außerhalb von ±10 % (1.980–2.420) liegt

#### Scenario: Kalender-Tag mit Festlegung
- **GIVEN** am 14. ist „Ruhetag“ festgelegt und erfasst sind 2.100 kcal bei Ruhe 2.200 kcal
- **WHEN** der Nutzer im Kalender den 14. antippt
- **THEN** zeigt die Ernährungskarte „Ruhetag · manuell“ und „2.100 von 2.200 kcal“

### Requirement: Aktualität

Ändert sich etwas, das die automatische Tagesart beeinflusst, MUST die App beim nächsten Anzeigen das neue Ziel verwenden. Dazu zählen ein beendetes oder gelöschtes Training, eine Änderung am Rhythmus und eine Tagesaktion wie Verschieben oder Überspringen. Historische Workout-Daten MUST dabei unverändert bleiben.

#### Scenario: Training überspringen
- **GIVEN** heute ist Push geplant und die Tageskarte zeigt das Trainingstag-Ziel
- **WHEN** der Nutzer Push überspringt und zum Tab „Essen“ wechselt
- **THEN** zeigt die Tageskarte das Ruhetag-Ziel

### Requirement: Speichern, Offline und Synchronisation

Ziele und Festlegung MUST offline änderbar sein und über den bestehenden Sync-Vertrag mit Versionsprüfung gespeichert werden, nämlich mit Zielplan bzw. Ernährungstag. Dieselbe Mutation-ID MUST NOT doppelt angewendet werden. Die neuen Felder MUST optional sein; fehlen sie, speichert der Server weder Ruhetag-Ziel noch Festlegung. Konflikte laufen über die bestehende Konfliktauflösung. Bei abgelaufener Sitzung MUST die Änderung in der Outbox bleiben.

#### Scenario: Offline festlegen
- **GIVEN** das Gerät ist offline
- **WHEN** der Nutzer für gestern „Ruhetag“ festlegt und danach eine Mahlzeit für gestern erfasst
- **THEN** zeigt die App sofort das Ruhetag-Ziel, die Outbox enthält einen zusammengefassten Stand des Tages, und nach Wiederverbindung hat der Server Einträge und Festlegung

#### Scenario: Abbruch und Retry
- **GIVEN** eine Mutation mit geänderten Zielen wurde gesendet, die Antwort ging aber verloren
- **WHEN** die App dieselbe Mutation erneut sendet
- **THEN** speichert der Server die Änderung genau einmal und die Version steigt nur einmal

#### Scenario: Ältere Mutation ohne neue Felder
- **GIVEN** der Server kennt Ruhetag-Ziele
- **WHEN** eine Mutation für den Zielplan ohne Ruhetag-Felder eintrifft
- **THEN** speichert der Server den Plan ohne Ruhetag-Ziel und lehnt die Mutation nicht ab

### Requirement: Serverseitige Prüfung und Nutzerisolation

Der Server MUST eine Mutation ablehnen, wenn ein Ziel die Regeln für Zielwerte verletzt oder die Tagesart nicht „Training“ oder „Rest“ ist. Ziele und Festlegung MUST nur für den angemeldeten Nutzer lesbar und änderbar sein.

#### Scenario: Ungültige Tagesart
- **WHEN** eine Mutation einen Ernährungstag mit der Tagesart „Refeed“ speichern will
- **THEN** antwortet der Server mit einem Validierungsfehler und speichert nichts

#### Scenario: Fremde Daten
- **GIVEN** Nutzer A und Nutzer B mit je eigenen Zielen
- **WHEN** Nutzer B seine Ziele abruft, nachdem Nutzer A ein Ruhetag-Ziel gespeichert hat
- **THEN** enthält die Antwort für Nutzer B kein Ruhetag-Ziel von Nutzer A
