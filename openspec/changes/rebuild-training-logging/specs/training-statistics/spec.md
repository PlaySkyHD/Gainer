# Spec Delta

## Purpose

Diese Capability definiert deterministische Trainingskennzahlen, den Übungsverlauf, das geschätzte 1RM und persönliche Rekorde einschließlich des Körpergewichtsanteils, identisch berechnet in App, Backend und für den Coach.

## ADDED Requirements

### Requirement: Datengrundlage der Kennzahlen

Kennzahlen MUST ausschließlich aus nicht gelöschten, abgeschlossenen eigenen Trainings und deren erfassten Sätzen berechnet werden. Aufwärmsätze werden standardmäßig ausgeschlossen, Dropsätze eingeschlossen; der Nutzer SHALL Aufwärmsätze per Einstellung einbeziehen können. Laufende Trainings fließen nicht ein.

#### Scenario: Aufwärmsätze ausgeschlossen
- **GIVEN** ein Training mit 1 Aufwärmsatz, 2 normalen Sätzen und 1 Dropsatz einer Übung
- **WHEN** die Satzanzahl mit Standardeinstellung berechnet wird
- **THEN** beträgt sie 3

#### Scenario: Gelöschtes Training
- **GIVEN** ein gelöschtes Training enthielt den bisher schwersten Satz
- **WHEN** Rekorde berechnet werden
- **THEN** wird dieser Satz nicht berücksichtigt

#### Scenario: Fremde Daten
- **GIVEN** Nutzer B besitzt Trainings mit derselben Basisübung
- **WHEN** Nutzer A seine Kennzahlen abruft
- **THEN** enthalten sie keine Sätze von Nutzer B

### Requirement: Körpergewicht aus Check-ins

Das für ein Training maßgebliche Körpergewicht MUST das Gewicht des jüngsten eigenen Check-ins sein, dessen lokales Datum am oder vor dem lokalen Starttag des Trainings liegt. Gibt es keinen solchen Check-in, gilt das Körpergewicht als fehlend. Änderungen oder Löschungen von Check-ins SHALL bei der nächsten Berechnung wirken.

#### Scenario: Jüngster Check-in vor dem Training
- **GIVEN** Check-ins am 10. Oktober mit 81 kg und am 14. Oktober mit 80 kg sowie ein Training am 15. Oktober
- **WHEN** das Körpergewicht des Trainings ermittelt wird
- **THEN** beträgt es 80 kg

#### Scenario: Check-in nach dem Training
- **GIVEN** der einzige Check-in liegt am 16. Oktober, das Training am 15. Oktober
- **WHEN** das Körpergewicht des Trainings ermittelt wird
- **THEN** gilt es als fehlend

#### Scenario: Check-in korrigiert
- **GIVEN** das Körpergewicht eines Trainings stammt aus einem Check-in mit 80 kg
- **WHEN** der Nutzer diesen Check-in auf 79 kg korrigiert
- **THEN** verwenden Kennzahlen und Rekorde dieses Trainings bei der nächsten Berechnung 79 kg

### Requirement: Effektives Satzgewicht

Das effektive Gewicht eines Satzes SHALL Zusatzgewicht × Zusatzgewichtsfaktor plus Körpergewicht aus Check-ins × Körpergewichtsfaktor betragen; bei assistierten Übungen wird das Unterstützungsgewicht abgezogen. Fehlt das Körpergewicht, MUST der Körpergewichtsanteil 0 sein und die Kennzahl als unvollständig gekennzeichnet werden.

#### Scenario: Klimmzug mit Zusatzlast
- **GIVEN** ein maßgebliches Körpergewicht von 80 kg und ein Klimmzugsatz mit 10 kg Zusatz bei Körpergewichtsfaktor 100 %
- **WHEN** das effektive Gewicht berechnet wird
- **THEN** beträgt es 90 kg

#### Scenario: Assistierter Klimmzug
- **GIVEN** ein maßgebliches Körpergewicht von 80 kg und ein assistierter Klimmzugsatz mit 20 kg Unterstützung
- **WHEN** das effektive Gewicht berechnet wird
- **THEN** beträgt es 60 kg

#### Scenario: Körpergewicht fehlt
- **GIVEN** ein Liegestütz-Training ohne vorherigen Check-in
- **WHEN** das Volumen berechnet wird
- **THEN** ist der Körpergewichtsanteil 0 und die Anzeige weist darauf hin, dass für korrekte Werte ein Check-in fehlt

### Requirement: Kennzahlen je Training und Übung

Das System SHALL je Training und Übung mindestens Satzanzahl, Wiederholungen gesamt, maximale Wiederholungen, Volumen (Summe effektives Gewicht × Wiederholungen), maximales Gewicht und gewichtetes Durchschnittsgewicht (Volumen / Wiederholungen) berechnen. Sätze mit 0 oder fehlenden Wiederholungen zählen nicht für das maximale Gewicht.

#### Scenario: Volumen und Durchschnitt
- **GIVEN** zwei Sätze 50 kg × 10 und 60 kg × 5 ohne Körpergewichtsanteil
- **WHEN** die Kennzahlen berechnet werden
- **THEN** beträgt das Volumen 800 kg, das Durchschnittsgewicht 53,33 kg und das maximale Gewicht 60 kg

### Requirement: Geschätztes 1RM

Das geschätzte 1RM eines Satzes MUST nach Epley als effektives Gewicht × (1 + Wiederholungen / 30) berechnet werden; bei genau einer Wiederholung gilt das effektive Gewicht, bei 0 oder fehlenden Wiederholungen 0. Das 1RM eines Trainings ist das Maximum seiner Sätze.

#### Scenario: 1RM berechnen
- **GIVEN** ein Satz 100 kg × 6 ohne Körpergewichtsanteil
- **WHEN** das geschätzte 1RM berechnet wird
- **THEN** beträgt es 120 kg

#### Scenario: Einzelwiederholung
- **GIVEN** ein Satz 140 kg × 1
- **WHEN** das geschätzte 1RM berechnet wird
- **THEN** beträgt es 140 kg

### Requirement: Persönliche Rekorde

Das System SHALL je Übung Rekordverläufe für maximales Gewicht, geschätztes 1RM, Volumen je Training und maximale Wiederholungen führen. Ein Wert MUST in chronologischer Reihenfolge nur dann als neuer Rekord gelten, wenn er den bisherigen Bestwert strikt übertrifft. Rekorde werden bei jeder Änderung der Historie neu berechnet.

#### Scenario: Gleichstand ist kein Rekord
- **GIVEN** chronologische Volumenwerte 500, 600, 600, 550, 700 einer Übung
- **WHEN** der Rekordverlauf berechnet wird
- **THEN** sind 500, 600 und 700 Rekordereignisse, der aktuelle Rekord ist 700

#### Scenario: Rekord nach Bearbeitung
- **GIVEN** der aktuelle Gewichtsrekord stammt aus einem Satz, der nachträglich von 120 kg auf 110 kg korrigiert wird
- **WHEN** Rekorde neu berechnet werden
- **THEN** gilt der nächstbeste verbleibende Wert als Rekord

#### Scenario: Neuer Rekord im Training
- **GIVEN** der bisherige 1RM-Rekord für Kniebeuge liegt bei 150 kg
- **WHEN** der Nutzer ein Training mit 130 kg × 6 beendet
- **THEN** hebt die Zusammenfassung einen neuen 1RM-Rekord von 156 kg hervor

### Requirement: Wiederholungsrekorde

Das System SHALL je Übung das maximale Gewicht für 1, 3, 5, 8, 10 und 12 Wiederholungen anzeigen, wobei ein Satz für eine Wiederholungszahl zählt, wenn er mindestens so viele Wiederholungen besitzt.

#### Scenario: Satz zählt für niedrigere Wiederholungszahlen
- **GIVEN** der einzige Satz einer Übung ist 100 kg × 8
- **WHEN** die Wiederholungsrekorde angezeigt werden
- **THEN** gilt 100 kg als Rekord für 1, 3, 5 und 8 Wiederholungen und für 10 und 12 gibt es keinen Wert

### Requirement: Übungsstatistik und Statistikbereich

Die App SHALL im Statistikbereich eine Übungsliste mit aktuellem Rekord sowie je Übung einen Verlauf von 1RM, maximalem Gewicht und Volumen über die Zeit anzeigen. Der Bereich MUST offline aus lokal vorhandenen Daten mit denselben Formeln wie das Backend berechnet werden.

#### Scenario: Offline-Statistik
- **GIVEN** das Gerät ist offline und lokal liegen zehn abgeschlossene Trainings vor
- **WHEN** der Nutzer die Statistik einer Übung öffnet
- **THEN** werden Verlauf und Rekorde aus den lokalen Daten berechnet und stimmen nach dem Sync mit den Backend-Werten überein

#### Scenario: Gleiche Formel für Coach
- **GIVEN** der Coach fragt die Übungsentwicklung eines Nutzers ab
- **WHEN** das Backend die Kennzahl liefert
- **THEN** entspricht sie dem in der App angezeigten Wert derselben Datengrundlage
