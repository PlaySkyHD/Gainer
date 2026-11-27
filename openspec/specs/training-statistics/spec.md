# training-statistics Specification

## Purpose
Deterministische Kennzahlen für Training, Gewicht und Ernährung: Volumen, 1RM, Rekorde und Übungsverlauf in App und Backend sowie die serverseitige Dashboard-Auswertung für Übersicht und Coach.

## Requirements

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

### Requirement: Gewichtsübersicht und Zeiträume

Das System MUST das aktuellste Gewicht, den arithmetischen 7-Tage-Durchschnitt und eine Gewichtsänderung in Kilogramm pro Woche aus den eigenen Check-ins berechnen. Es SHALL Gewichtsreihen für einen angefragten Zeitraum von 1 bis 365 Tagen (Standard 30) bereitstellen und Tage ohne Eintrag nicht als Gewicht null behandeln.

#### Scenario: 7-Tage-Durchschnitt berechnen

- **GIVEN** ein Nutzer besitzt in den letzten sieben lokalen Kalendertagen fünf Gewichtseinträge
- **WHEN** die Gewichtsübersicht berechnet wird
- **THEN** entspricht der 7-Tage-Durchschnitt dem arithmetischen Mittel genau dieser fünf Werte und die Datenabdeckung wird als fünf von sieben Tagen ausgewiesen

#### Scenario: Zeitraum auswählen

- **GIVEN** ein Nutzer besitzt Gewichtseinträge über mehr als 90 Tage
- **WHEN** die Übersicht den Zeitraum von 30 Tagen abfragt
- **THEN** enthält die Zeitreihe ausschließlich seine Einträge im definierten 30-Tage-Fenster in chronologischer Reihenfolge

### Requirement: Gewichtstrend mit ausreichender Datengrundlage

Das System SHALL die Gewichtsänderung pro Woche anhand einer dokumentierten, versionierten und für identische Eingaben reproduzierbaren Trendberechnung bestimmen. Es MUST bei weniger als drei Gewichtseinträgen im betrachteten Zeitraum statt eines Trends den Zustand `unzureichende Daten` liefern.

#### Scenario: Reproduzierbarer Trend

- **GIVEN** dieselben datierten Gewichtseinträge und dieselbe Berechnungsversion
- **WHEN** der Trend mehrfach oder für verschiedene Clients berechnet wird
- **THEN** sind Ergebnis, Einheit, Zeitraum und Berechnungsversion identisch

#### Scenario: Zu wenige Gewichtseinträge

- **GIVEN** im gewählten Zeitraum existieren nur zwei Gewichtseinträge
- **WHEN** der Gewichtstrend angefordert wird
- **THEN** liefert das System keinen numerischen Wochenwert und kennzeichnet die Datengrundlage als unzureichend

### Requirement: Ernährungskennzahlen

Das System MUST für den angefragten Zeitraum Durchschnittswerte für Kalorien, Protein, Kohlenhydrate und Fett ausschließlich über Tage berechnen, an denen der jeweilige Wert erfasst wurde. Fehlende Werte dürfen nicht als null einfließen; zu jedem Wert SHALL die Anzahl berücksichtigter Tage ausgegeben werden.

#### Scenario: Teilweise erfasste Ernährung

- **GIVEN** ein Nutzer hat in sieben Tagen an fünf Tagen Kalorien und an drei Tagen Protein erfasst
- **WHEN** die 7-Tage-Kennzahlen berechnet werden
- **THEN** verwendet der Kaloriendurchschnitt fünf und der Proteindurchschnitt drei Werte und weist beide Abdeckungen getrennt aus

#### Scenario: Keine Werte für eine Kennzahl

- **GIVEN** im Zeitraum wurde kein Fettwert erfasst
- **WHEN** die Ernährungskennzahlen berechnet werden
- **THEN** liefert das System für Fett `keine Daten` statt eines Durchschnitts von null

### Requirement: Deterministische Übungsentwicklung

Das System MUST pro Übung und Zeitraum den besten Satz, verwendetes Gewicht, Wiederholungen, Gesamtvolumen, Anzahl abgeschlossener Trainings und geschätztes 1RM ausschließlich aus abgeschlossenen eigenen Sätzen berechnen. Die Formel für das geschätzte 1RM SHALL dokumentiert und versioniert sein; nicht geeignete Sätze müssen als nicht berechenbar behandelt werden.

#### Scenario: Übungsfortschritt berechnen

- **GIVEN** ein Nutzer besitzt mehrere abgeschlossene Trainings derselben stabilen Übungs-ID im gewählten Zeitraum
- **WHEN** er den Übungsfortschritt abruft
- **THEN** werden die Kennzahlen reproduzierbar aus genau diesen Sätzen berechnet und mit Zeitraum sowie Berechnungsversion ausgegeben

#### Scenario: Laufendes Workout ausschließen

- **GIVEN** ein Nutzer besitzt ein abgeschlossenes und ein noch laufendes Training derselben Übung
- **WHEN** der Fortschritt berechnet wird
- **THEN** fließen ausschließlich Sätze des abgeschlossenen Trainings ein

#### Scenario: Fremde oder ungeeignete Sätze ausschließen

- **GIVEN** es existieren Sätze anderer Nutzer oder Sätze ohne für das geschätzte 1RM geeignete Werte
- **WHEN** die Kennzahlen des authentifizierten Nutzers berechnet werden
- **THEN** fließen fremde Sätze nie ein und ungeeignete Sätze erzeugen keinen geschätzten 1RM-Wert

### Requirement: Dashboard-Zusammenfassung

Das System SHALL für den authentifizierten Nutzer eine Übersicht aus aktivem Ziel, aktuellstem Gewicht, 7-Tage-Gewichtsdurchschnitt, Gewichtstrend, durchschnittlichen Kalorien und Protein sowie der Anzahl abgeschlossener Trainings der letzten 7 Tage bereitstellen.

#### Scenario: Vollständige Dashboard-Daten

- **GIVEN** ein Nutzer besitzt ein aktives Ziel sowie ausreichende Gewichts-, Ernährungs- und Workout-Daten
- **WHEN** er das Dashboard öffnet
- **THEN** zeigt die Übersicht ausschließlich seine deterministisch berechneten Kennzahlen mit den zugehörigen Zeiträumen

#### Scenario: Teilweise fehlende Dashboard-Daten

- **GIVEN** ein Nutzer besitzt ein Ziel und Gewichtseinträge, aber keine Ernährungs- oder Workout-Daten
- **WHEN** er das Dashboard öffnet
- **THEN** bleiben die verfügbaren Kennzahlen sichtbar und die fehlenden Bereiche werden jeweils als `keine Daten` gekennzeichnet

### Requirement: Analytics bleiben unabhängig von der KI

Das System MUST alle numerischen Fortschrittskennzahlen ohne Beteiligung eines Sprachmodells berechnen und SHALL sie über denselben nutzergebundenen Vertrag an UI und AI Coach liefern.

#### Scenario: OpenAI ist nicht erreichbar

- **GIVEN** der externe KI-Dienst ist nicht verfügbar
- **WHEN** der Nutzer Dashboard oder Übungsfortschritt abruft
- **THEN** werden alle deterministischen Kennzahlen weiterhin vollständig bereitgestellt

#### Scenario: UI und AI verwenden dieselbe Kennzahl

- **GIVEN** UI und AI Coach fragen dieselbe Kennzahl für denselben Nutzer, Zeitraum und Datenstand ab
- **WHEN** das Backend beide Anfragen verarbeitet
- **THEN** erhalten beide denselben Wert und dieselbe Berechnungsversion

### Requirement: Verlauf im Statistikbereich

Die App SHALL im Statistikbereich einen Bereich „Verlauf“ mit Zeitraum-Umschalter (4 Wochen, 3 Monate, 1 Jahr, Alle; Standard 3 Monate) und je einer Kachel für Trainings pro Woche, Ø Trainingsdauer, Gesamtzeit, Volumen, Sätze, Wiederholungen, Ø Wiederholungen pro Satz und Körpergewicht anzeigen. Ohne gezähltes Training und ohne Check-in MUST der Bereich fehlen. Hat nur der gewählte Zeitraum keine Daten, SHALL statt der Kacheln ein Hinweis erscheinen.

#### Scenario: Zeitraum wechseln
- **GIVEN** heute ist Samstag, 17. Oktober 2026, und es gibt drei beendete Trainings
- **WHEN** der Nutzer „4 W“ wählt
- **THEN** beginnt der Zeitraum am Montag, 21. September 2026, und die Kachel Krafttrainings zeigt „Ø 0,8 pro Woche“

#### Scenario: Zeitraum ohne Daten
- **GIVEN** das einzige Training liegt mehr als drei Monate zurück
- **WHEN** der Nutzer die Statistik mit dem Zeitraum 3 Monate öffnet
- **THEN** erscheint statt der Kacheln ein Hinweis, und mit „Alle“ erscheinen die Kacheln

#### Scenario: Große Schrift
- **GIVEN** die Textgröße ist 2,0
- **WHEN** der Bereich „Verlauf“ erscheint
- **THEN** stehen die Kacheln untereinander und nichts läuft über

### Requirement: Abschnitte des Verlaufs

Jede Verlaufskachel MUST einen Wert für den ganzen Zeitraum und eine Linie je Woche (4 Wochen, 3 Monate) oder je Kalendermonat (1 Jahr, Alle) zeigen. Wochen beginnen montags, der letzte Abschnitt enthält den heutigen Tag. „Alle“ beginnt im Monat des ersten gezählten Trainings oder Check-ins.

#### Scenario: Ein Jahr
- **GIVEN** heute ist der 26. November 2026
- **WHEN** der Verlauf für 1 Jahr berechnet wird
- **THEN** beginnt er am 1. Dezember 2025 und hat zwölf Monatsabschnitte

### Requirement: Kennzahlen des Verlaufs

Sätze, Wiederholungen und Volumen im Verlauf MUST derselben Datengrundlage und denselben Formeln folgen wie Rekorde und Übungsstatistik, einschließlich der Einstellung für Aufwärmsätze. Die Dauer eines Trainings ist die Zeit von Start bis Ende. Trainings pro Woche ist die Zahl der Trainings im Zeitraum geteilt durch die Tage vom ersten Tag des Zeitraums bis heute, geteilt durch sieben.

#### Scenario: Werte für drei Monate
- **GIVEN** heute ist Samstag, 17. Oktober 2026, und es gibt drei beendete Trainings à 60 Minuten mit zusammen 6 gezählten Sätzen, 38 Wiederholungen und 3.550 kg Volumen
- **WHEN** der Nutzer die Statistik mit dem Zeitraum 3 Monate öffnet
- **THEN** zeigen die Kacheln „Ø 0,2 pro Woche“, „Ø 60 min“, „3:00 h“, „3.550 kg“, „6“, „38“ und „Ø 6,3“

### Requirement: Körpergewicht im Verlauf

Die Körpergewichtskachel MUST als Wert den jüngsten Check-in im Zeitraum zeigen und als Linie den Durchschnitt der Check-ins je Abschnitt. Abschnitte ohne Check-in MUST leer bleiben und nicht als 0 gelten; die Linie überbrückt sie nicht.

#### Scenario: Woche ohne Check-in
- **GIVEN** Check-ins in der ersten und letzten von vier Wochen
- **WHEN** der Verlauf für 4 Wochen berechnet wird
- **THEN** hat die Körpergewichtslinie Punkte nur für diese zwei Wochen

### Requirement: Gleiche Kennzahlen in App und Server

Rechnet die App eine Kennzahl selbst, MUST der Server sie für den MCP-Server gleich rechnen: Verlauf, Trainingstage, Muskelvolumen, Cardio-Kennzahlen, Ernährungsdurchschnitt und Rhythmus-Vorschau mit Tagesart. Je Berechnung SHALL eine Fixture unter `contracts/fixtures/` Eingaben und Ergebnisse festhalten, die App- und Server-Tests prüfen. Nur Werte aus Einstellungen, die allein auf dem Telefon liegen, DÜRFEN fehlen.

#### Scenario: Fixture des Verlaufs
- **GIVEN** die Fixture `training-trends.json` mit Wochen über das Ende der Sommerzeit und Aufwärmsätzen
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide dieselben Abschnitte, Summen und Durchschnitte

#### Scenario: Automatische Tagesart
- **GIVEN** ein erfasster Ernährungstag ohne festgelegte Tagesart unter einem Ziel mit Ruhetag-Ziel
- **WHEN** der Server den Ernährungsdurchschnitt rechnet
- **THEN** leitet der Server die Tagesart wie die App aus beendeten Trainings und der Rhythmus-Vorschau ab und nutzt am Ruhetag das Ruhetag-Ziel

#### Scenario: Fixture der Rhythmus-Vorschau
- **GIVEN** die Fixture `training-schedule.json` mit Zyklus und festen Tagen, Verschiebungen, Überspringen, archivierten Plänen und Trainings rund um Mitternacht und die Zeitumstellung
- **WHEN** die Tests der App und des Servers sie berechnen
- **THEN** ergeben beide je Tag dieselbe Tagesart, dieselben Trainings mit Status und dieselbe automatische Tagesart sowie dasselbe nächste offene Training
