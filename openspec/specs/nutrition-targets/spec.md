# nutrition-targets Specification

## Purpose
Manuelle Ernährungsziele für Trainingstage und optional Ruhetage mit Salzobergrenze und Ballaststoffziel. Änderungen gelten ab heute; die Tagesart ergibt sich aus Training und Rhythmus oder wird manuell festgelegt.

## Requirements

### Requirement: Transparente Makro-Energiebilanz

Trainingstag- und Ruhetag-Ziel SHALL je die Eingabeart `Gramm` oder `Prozent` haben. Im Gramm-Modus MUST die App die Makroenergie mit 4/4/9 kcal pro Gramm Protein, Kohlenhydrate und Fett berechnen und als „Aus den Makros: … kcal“ zeigen. Im Prozent-Modus MÜSSEN die Anteile zusammen 100 % ergeben, und die App leitet die Grammziele mit 4/4/9 ab. Ein Wechsel der Eingabeart MUST umrechnen, ohne Werte zu verlieren. Die App DARF keine Verteilung vorschlagen.

#### Scenario: Makroenergie anzeigen
- **GIVEN** der Gramm-Modus mit 180 g Protein, 290 g Kohlenhydraten und 80 g Fett
- **WHEN** der Nutzer die Ziele bearbeitet
- **THEN** steht unter den Eingaben „Aus den Makros: 2.600 kcal.“

#### Scenario: Prozentverteilung in Gramm umrechnen
- **GIVEN** eine manuell gewählte Verteilung aus 30 Prozent Protein, 40 Prozent Kohlenhydraten und 30 Prozent Fett bei 2.000 kcal
- **WHEN** der Nutzer die Ziele speichert
- **THEN** speichert die Anwendung Eingabeart, Prozentwerte und die abgeleiteten Grammwerte (150 g Protein, 200 g Kohlenhydrate, etwa 67 g Fett) im selben Ziel

#### Scenario: Prozentwerte ergeben nicht 100 Prozent
- **GIVEN** die drei eingegebenen Makroanteile ergeben zusammen 95 Prozent
- **WHEN** der Nutzer die Ziele bearbeitet
- **THEN** ist „Speichern“ deaktiviert und der Editor meldet, dass die Makroanteile zusammen 100 % ergeben müssen

### Requirement: Zugänglicher Tagesfortschritt

Für Kilokalorien, Protein, Kohlenhydrate und Fett MUST sie jeweils aufgenommenen Wert, gültigen Zielwert, verbleibenden beziehungsweise überschrittenen Wert und einen visuellen Fortschritt darstellen. Der Zustand MUST zusätzlich textuell und für Screenreader verständlich sein; Farbe allein DARF ihn nicht vermitteln. Ein Überschreiten MUST sichtbar bleiben und DARF den Zahlenwert nicht bei 100 Prozent abschneiden.

#### Scenario: Ziel teilweise erreicht

- **GIVEN** ein Tag enthält 1.500 von 2.500 kcal und 120 von 180 g Protein
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** zeigt sie für beide Werte den proportionalen Fortschritt und die jeweils verbleibende Menge numerisch sowie zugänglich an

#### Scenario: Fettziel überschritten

- **GIVEN** ein Tag enthält 90 g Fett bei einem Ziel von 70 g
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** kennzeichnet sie 20 g Überschreitung textuell und visuell, ohne die Aufnahme als exakt 70 g auszugeben

#### Scenario: Einträge besitzen fehlende Makros

- **GIVEN** mindestens ein Ernährungseintrag des Tages hat keine verwertbare Proteinangabe
- **WHEN** der Proteinfortschritt berechnet wird
- **THEN** kennzeichnet die Anwendung die Proteinsumme als unvollständig und stellt sie nicht als verlässlich verbleibenden Zielwert dar

#### Scenario: Für den Tag gilt kein Ziel

- **GIVEN** für den geöffneten Tag existiert keine wirksame Zielversion
- **WHEN** die Tageszusammenfassung angezeigt wird
- **THEN** zeigt sie die aufgenommenen Nährwerte ohne irreführende Progressbars und bietet „Ziele festlegen“ an

### Requirement: Nutzerisolation und keine automatischen Zielwerte

Ziele, Fortschrittswerte und Sync-Changes MUST ausschließlich aus Daten des authentifizierten Nutzers entstehen. Kalorien und Makroverteilung MÜSSEN manuelle Nutzereingaben sein. Weder Request-Metadaten noch AI-Ausgaben DÜRFEN eine Nutzer-ID bestimmen, Zielwerte vorschlagen oder eine mutierende Zieloperation auslösen.

#### Scenario: Fremden Zielplan adressieren

- **GIVEN** Nutzer A kennt die Zielplan-ID von Nutzer B
- **WHEN** Nutzer A sie liest oder verändert
- **THEN** behandelt das Backend sie wie eine nicht vorhandene Ressource und offenbart keine Zielwerte

#### Scenario: Coach nennt abweichende Zielwerte

- **GIVEN** eine AI-Antwort enthält numerische Zielwerte oder eine Aufforderung zum Speichern
- **WHEN** das Backend die Antwort verarbeitet
- **THEN** werden weder Ziele noch Ernährungstag verändert und die Werte werden nicht als Zielvorschlag in die Anwendung übernommen

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

Speichert der Nutzer geänderte Ziele, MUST die Änderung ab dem heutigen lokalen Tag gelten. Tage davor MUST weiterhin mit dem Ziel verglichen werden, das an ihnen galt. Mehrere Änderungen am selben Tag MUST zu einem einzigen Ziel für diesen Tag führen, und zwar zum zuletzt gespeicherten. Künftig beginnende Zielversionen aus älteren App-Ständen MUST beim Speichern verworfen werden.

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
- **THEN** wird gestern mit dem Ruhetag-Ziel verglichen, und in der Übersicht bleibt Pull als verpasst markiert

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

Das Ziel eines Tages MUST sich aus den an diesem Tag gültigen Zielen ergeben. Gibt es ein Ruhetag-Ziel und zählt der Tag als Ruhetag, gilt das Ruhetag-Ziel. Sonst gilt das Trainingstag-Ziel. Tageskarte und Übersicht SHALL neben dem Ziel die Tagesart zeigen, „Trainingstag“ oder „Ruhetag“, mit dem Zusatz „manuell“ bei einer Festlegung. Ohne Ruhetag-Ziel MUST keine Tagesart angezeigt werden.

#### Scenario: Ruhetag in der Tageskarte
- **GIVEN** Trainingstag 2.600 kcal und Ruhetag 2.200 kcal, heute ist laut Rhythmus Ruhetag, und erfasst sind 1.800 kcal
- **WHEN** der Nutzer den Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte „Ruhetag“ und „1.800 von 2.200 kcal“ mit 400 kcal verbleibend

#### Scenario: Ohne Ziele
- **GIVEN** der Nutzer hat keine Ziele
- **WHEN** er den Tab „Essen“ öffnet
- **THEN** zeigt die Tageskarte die aufgenommenen Werte ohne Fortschrittsbalken und bietet „Ziele festlegen“ an

### Requirement: Übersicht und Durchschnitte

Die Ernährungskarte der Übersicht SHALL das Ziel des Tages und die Tagesart zeigen. Sie SHALL dieselbe Auswahl „Zählt als“ anbieten wie der Tab „Essen“. Der Zielvergleich der Durchschnitte MUST pro Tag das Ziel des Tages verwenden. Das Monatsraster MUST NOT eine neue Markierung für die Tagesart bekommen.

#### Scenario: Durchschnitt über Trainings- und Ruhetage
- **GIVEN** Training 2.600 kcal und Ruhe 2.200 kcal; erfasst sind 2 Trainingstage mit je 2.600 kcal und 1 Ruhetag mit 2.600 kcal
- **WHEN** der Nutzer die Durchschnitte über diese 3 Tage ansieht
- **THEN** ist Ø Ziel 2.466,67 kcal (angezeigt gerundet „2.467 kcal“), und 2 von 3 Tagen liegen im Zielbereich, weil 2.600 beim Ruhetag-Ziel 2.200 außerhalb von ±10 % (1.980–2.420) liegt

#### Scenario: Tag mit Festlegung in der Übersicht
- **GIVEN** am 14. ist „Ruhetag“ festgelegt und erfasst sind 2.100 kcal bei Ruhe 2.200 kcal
- **WHEN** der Nutzer in der Übersicht den 14. wählt
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

### Requirement: Salzobergrenze

Die Ziele SHALL eine gemeinsame Salzobergrenze pro Tag haben. Ohne eigenen Wert SHALL 6 g gelten. Die Tageskarte SHALL „Salz x / y g“ zeigen und den Balken ab der Grenze in Warnfarbe darstellen.

#### Scenario: Standardgrenze
- **GIVEN** Ziele ohne eigene Salzgrenze
- **WHEN** der Tag 4,2 g Salz enthält
- **THEN** zeigt die Tageskarte „Salz 4,2 / 6 g“

#### Scenario: Eigene Grenze
- **GIVEN** der Nutzer setzt in den Zielen „Salz höchstens 5 g“
- **WHEN** der Tag 5,5 g Salz enthält
- **THEN** zeigt die Tageskarte den Salzbalken in Warnfarbe

### Requirement: Ballaststoffziel

Die Ziele SHALL ein Ballaststoffziel pro Tag als Mindestwert haben. Ohne eigenen Wert SHALL 30 g gelten. Das Ziel SHALL für Trainings- und Ruhetage gleich gelten. Die Tageskarte SHALL „Ballaststoffe x / y g“ zeigen. Der Balken MUST NOT eine Warnfarbe verwenden und SHALL ab dem Ziel voll sein.

#### Scenario: Standardziel
- **GIVEN** Ziele ohne eigenes Ballaststoffziel
- **WHEN** der Tag 18 g Ballaststoffe enthält
- **THEN** zeigt die Tageskarte „Ballaststoffe 18 / 30 g“

#### Scenario: Ziel überschritten
- **GIVEN** Ziele mit „Ballaststoffe mindestens 25 g“
- **WHEN** der Tag 34 g Ballaststoffe enthält
- **THEN** zeigt die Tageskarte „Ballaststoffe 34 / 25 g“ mit vollem Balken ohne Warnfarbe

#### Scenario: Ältere Zielversion
- **GIVEN** eine Zielversion ohne Ballaststoffziel
- **WHEN** der Server sie liest
- **THEN** ist ihr Ballaststoffziel leer, der wirksame Wert 30 g und die Version gilt beim Abgleich als unverändert
