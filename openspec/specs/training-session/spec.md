# training-session Specification

## Purpose
Lebenszyklus und Erfassung eines Krafttrainings in der iPhone-App: starten, Sätze inline erfassen, Vorwerte, Aufwärmhinweis, beenden, bearbeiten, löschen, Tagebuch und der Aufbau der Trainings-Screens.

## Requirements

### Requirement: Leeres Training starten

Das System MUST online wie offline ein leeres Training mit stabiler ID, auf Sekunden gerundeter Startzeit, ohne Endzeit und ohne Übungsblöcke anlegen können. Der Titel SHALL vorbelegt werden und bleibt editierbar.

#### Scenario: Leeres Training offline starten
- **GIVEN** das Gerät ist offline und es existiert kein aktives Training
- **WHEN** der Nutzer „Leeres Training“ wählt
- **THEN** wird sofort lokal ein Training mit stabiler ID, aktueller Startzeit und leerer Übungsliste angelegt und für die Synchronisation vorgemerkt

#### Scenario: Speicherfehler beim Start
- **GIVEN** das lokale Speichern schlägt fehl
- **WHEN** der Nutzer ein Training startet
- **THEN** zeigt die App einen Fehler, es entsteht kein halb angelegtes Training und kein Outbox-Eintrag

### Requirement: Training wiederholen

Der Nutzer SHALL ein früheres Training als Vorlage für ein neues Training verwenden können. Das neue Training übernimmt Titel, Übungsblöcke, Reihenfolge, Superset-Zuordnung und Satztypen, aber keine Satzwerte. Vor dem Start wählt der Nutzer die Vorwertquelle.

#### Scenario: Training wiederholen
- **GIVEN** ein früheres Training „Push“ mit Bankdrücken (1 Aufwärmsatz, 3 normale Sätze)
- **WHEN** der Nutzer „Training wiederholen“ mit der Vorwertquelle „dieses Training“ startet
- **THEN** entsteht ein neues aktives Training „Push“ mit vier leeren Bankdrück-Sätzen gleicher Typen, deren Platzhalter die Werte des früheren Trainings zeigen

#### Scenario: Wiederholtes Training später gelöscht
- **GIVEN** ein Training wurde aus Training X wiederholt
- **WHEN** Training X gelöscht wird
- **THEN** bleibt das neue Training vollständig erhalten und seine Vorwerte fallen auf die Quelle „nach Übung“ zurück

### Requirement: Genau ein aktives Training

Ein Training ohne Endzeit SHALL als aktiv gelten, unabhängig vom Kalendertag. Das System MUST höchstens ein aktives Training pro Nutzer zulassen und beim Versuch eines zweiten Starts das bestehende anbieten.

#### Scenario: Zweites Training starten
- **GIVEN** ein Training ohne Endzeit existiert
- **WHEN** der Nutzer ein weiteres Training starten möchte
- **THEN** bietet die App an, das aktive Training fortzusetzen oder es zuerst zu beenden, und legt kein zweites aktives Training an

#### Scenario: Training über Mitternacht
- **GIVEN** ein um 23:30 gestartetes Training ohne Endzeit
- **WHEN** der Nutzer die App um 00:15 öffnet
- **THEN** wird dasselbe Training weiterhin als aktiv mit fortlaufender Trainingszeit angezeigt

### Requirement: Aktive Session minimieren statt pausieren

Eine aktive Session MUST keine Pausenfunktion besitzen. Der Nutzer SHALL sie minimieren können; die App zeigt dann eine kompakte Leiste mit Trainingszeit seit Start, über die das Training wieder geöffnet wird.

#### Scenario: Minimieren und andere Bereiche nutzen
- **GIVEN** ein aktives Training ist geöffnet
- **WHEN** der Nutzer es minimiert und ein historisches Training ansieht
- **THEN** bleibt das aktive Training unverändert aktiv, die kompakte Leiste zeigt die weiterlaufende Trainingszeit und ein Tipp darauf öffnet es wieder

#### Scenario: App-Neustart während aktiver Session
- **GIVEN** ein aktives Training ist lokal gespeichert
- **WHEN** die App beendet und neu gestartet wird
- **THEN** wird das Training mit seinem zuletzt gespeicherten Stand und der aus der Startzeit berechneten Trainingszeit wiederhergestellt

### Requirement: Training beenden mit Fehlwerte-Dialog

Beim Beenden MUST das System prüfen, ob Sätze fehlende Pflichtwerte haben. Gibt es solche Sätze, SHALL ein Dialog die Optionen „Vorwerte übernehmen“, „Trotzdem beenden“ und „Weitertrainieren“ anbieten. Ohne fehlende Werte wird direkt beendet.

#### Scenario: Vorwerte übernehmen
- **GIVEN** ein Satz ohne Wiederholungen und mit vorhandenem Vorwert 100 kg × 8
- **WHEN** der Nutzer beendet und „Vorwerte übernehmen“ wählt
- **THEN** werden nur die leeren Felder mit 100 kg beziehungsweise 8 gefüllt, bereits eingetragene Werte bleiben unverändert und die Endzeit wird gesetzt

#### Scenario: Vorwert fehlt bei Übernahme
- **GIVEN** ein leerer Satz ohne passenden Vorwert
- **WHEN** der Nutzer „Vorwerte übernehmen“ wählt
- **THEN** bleiben dessen Felder leer und es wird weder 0 noch ein geschätzter Wert eingesetzt

#### Scenario: Trotzdem beenden
- **GIVEN** Sätze mit fehlenden Werten
- **WHEN** der Nutzer „Trotzdem beenden“ wählt
- **THEN** wird die Endzeit gesetzt und die fehlenden Werte bleiben leer

#### Scenario: Weitertrainieren
- **GIVEN** der Fehlwerte-Dialog ist offen
- **WHEN** der Nutzer „Weitertrainieren“ wählt
- **THEN** bleibt das Training ohne Endzeit aktiv und unverändert

### Requirement: Trainingszusammenfassung

Nach dem Beenden SHALL die App eine Zusammenfassung mit Dauer, Anzahl erfasster Sätze, Wiederholungen, Volumen und dem besten Satz je Übung anzeigen und neu erreichte persönliche Rekorde hervorheben.

#### Scenario: Zusammenfassung nach Abschluss
- **GIVEN** ein Training mit einem erfassten Satz 20 kg × 6 einer Kraftübung ohne Körpergewichtsanteil
- **WHEN** der Nutzer das Training beendet
- **THEN** zeigt die Zusammenfassung 1 Satz, 6 Wiederholungen, 120 kg Volumen und 20 kg × 6 als besten Satz

### Requirement: Trainingsmetadaten

Ein Training SHALL Titel, Trainingsnotiz sowie Start- und Endzeit besitzen, die jederzeit bearbeitet werden können. Die Endzeit MUST nach der Startzeit liegen. Ein Training speichert kein eigenes Körpergewicht; maßgeblich ist das Körpergewicht aus den täglichen Check-ins (siehe `training-statistics`).

#### Scenario: Ungültige Endzeit
- **GIVEN** ein abgeschlossenes Training mit Start 18:00
- **WHEN** der Nutzer die Endzeit auf 17:30 setzt
- **THEN** wird die Änderung mit einem Feldfehler abgelehnt und der vorherige Stand bleibt erhalten

#### Scenario: Kein Körpergewichtsfeld im Training
- **GIVEN** ein aktives oder historisches Training
- **WHEN** der Nutzer den Trainingskopf öffnet
- **THEN** zeigt er Titel, Startzeit, Endzeit und Notiz, aber kein Eingabefeld für das Körpergewicht

### Requirement: Historische Trainings bearbeiten

Das System MUST abgeschlossene Trainings im Tagebuch genauso bearbeitbar machen wie aktive: Metadaten, Übungsblöcke und Sätze. Änderungen SHALL Vorwerte, Kennzahlen und Rekorde bei der nächsten Berechnung beeinflussen.

#### Scenario: Satz in abgeschlossenem Training ändern
- **GIVEN** ein abgeschlossenes Training mit dem Satz 100 kg × 8
- **WHEN** der Nutzer ihn auf 100 kg × 10 ändert
- **THEN** wird die Änderung lokal gespeichert, synchronisiert und der Übungsverlauf zeigt 100 kg × 10

#### Scenario: Stammdatenänderung wirkt nicht rückwirkend
- **GIVEN** ein abgeschlossenes Training mit der Übung „Bankdrücken“ und dem Plan „Push“
- **WHEN** der Nutzer später die Übung umbenennt oder den Plan ändert
- **THEN** zeigt das historische Training weiterhin den gespeicherten Übungsnamen und seine eigenen Blöcke und Sätze

### Requirement: Training löschen

Der Nutzer SHALL jedes eigene Training nach Bestätigung löschen können. Ein gelöschtes Training MUST sofort aus Tagebuch, Vorwerten, Kennzahlen und Rekorden verschwinden, zählt nicht mehr als Erfüllung eines geplanten Trainings und als Löschung synchronisiert werden.

#### Scenario: Training offline löschen
- **GIVEN** ein abgeschlossenes Training und keine Netzverbindung
- **WHEN** der Nutzer das Löschen bestätigt
- **THEN** verschwindet es sofort aus dem Tagebuch und die Löschung wird nach Wiederverbindung genau einmal synchronisiert

#### Scenario: Aktives Training löschen
- **GIVEN** ein aktives Training mit erfassten Sätzen
- **WHEN** der Nutzer es löscht
- **THEN** existiert danach kein aktives Training mehr und Pausentimer sowie Live Activity werden beendet

### Requirement: Tagebuch

Die App SHALL alle nicht gelöschten Trainings im Tagebuch nach Startzeit absteigend, gruppiert nach Monat mit Anzahl der Trainings, anzeigen. Jeder Eintrag zeigt Datum, Titel, Dauer und die Übungen mit Satzanzahl.

#### Scenario: Monatsgruppen
- **GIVEN** zwei Trainings im Oktober und eines im September
- **WHEN** der Nutzer das Tagebuch öffnet
- **THEN** erscheinen die Oktober-Trainings neuestes zuerst unter „Oktober“ mit Anzahl 2, danach September mit Anzahl 1

### Requirement: Nutzerisolierte Trainings

Das System MUST Trainings, Übungsblöcke und Sätze ausschließlich dem authentifizierten Nutzer zuordnen und Zugriffe auf fremde Trainings-IDs ohne Datenoffenlegung ablehnen.

#### Scenario: Fremdes Training adressieren
- **GIVEN** Nutzer A kennt die Trainings-ID von Nutzer B
- **WHEN** Nutzer A diese ID in einer Sync-Mutation zum Bearbeiten oder Löschen verwendet
- **THEN** lehnt das Backend die Mutation ohne Offenlegung von Inhalten ab und das Training von B bleibt unverändert

#### Scenario: Wiederholte Sync-Mutation
- **GIVEN** eine Trainingsänderung wurde bereits erfolgreich verarbeitet
- **WHEN** der Client sie nach einem Netzwerkabbruch mit derselben Mutations-ID erneut sendet
- **THEN** antwortet das Backend mit dem bereits gespeicherten Ergebnis und es entsteht keine doppelte Wirkung

### Requirement: Übungsblöcke hinzufügen

Der Nutzer SHALL einem Training eine oder mehrere eigene oder Basis-Übungen hinzufügen können. Jede Übung wird als eigener Block mit Übungsname-Snapshot und einem leeren normalen Satz angehängt. Werden mehrere Übungen als Superset gewählt, erhalten ihre Blöcke dieselbe neue Superset-ID.

#### Scenario: Einzelne Übung hinzufügen
- **GIVEN** ein aktives Training mit einem Block
- **WHEN** der Nutzer „Kniebeuge“ hinzufügt
- **THEN** erscheint am Ende ein Kniebeuge-Block mit einem leeren normalen Satz und ohne Superset-ID

#### Scenario: Superset hinzufügen
- **GIVEN** ein aktives Training
- **WHEN** der Nutzer „Bizepscurl“ und „Trizepsdrücken“ gemeinsam als Superset hinzufügt
- **THEN** entstehen zwei benachbarte Blöcke mit derselben neuen Superset-ID, die als Gruppe A/B dargestellt werden

#### Scenario: Archivierte oder fremde Übung
- **GIVEN** eine archivierte eigene Übung oder die ID einer fremden Übung
- **WHEN** sie einem Training hinzugefügt werden soll
- **THEN** wird sie in der Auswahl nicht angeboten beziehungsweise vom Backend ohne Datenoffenlegung abgelehnt

### Requirement: Superset-Gruppierung

Das System MUST nur unmittelbar benachbarte Blöcke mit gleicher, nicht leerer Superset-ID als eine Gruppe darstellen. Positionen innerhalb einer Gruppe SHALL mit A bis Z beschriftet werden. Der Nutzer kann einen Block aus einem Superset lösen oder mit dem Nachbarblock verbinden.

#### Scenario: Unterbrochene Superset-ID
- **GIVEN** Blöcke A (Superset x), B (Superset y), C (Superset x)
- **WHEN** die Gruppen berechnet werden
- **THEN** entstehen drei separate Gruppen

### Requirement: Inline-Satzerfassung ohne Abschluss-Klick

Gewicht und Wiederholungen SHALL direkt in der Satzzeile über eine numerische Tastatur erfasst werden; Komma und Punkt gelten als Dezimaltrennzeichen. Jede gültige Eingabe MUST sofort lokal gespeichert werden. Ein separater Abschluss-Klick je Satz existiert nicht.

#### Scenario: Satz eintragen
- **GIVEN** ein leerer normaler Satz einer Kraftübung
- **WHEN** der Nutzer „102,5“ ins Gewichtsfeld und „8“ ins Wiederholungsfeld tippt
- **THEN** ist der Satz mit 102,5 kg × 8 lokal gespeichert, für den Sync vorgemerkt und gilt als erfasst

#### Scenario: Ungültige Eingabe
- **GIVEN** eine Satzzeile
- **WHEN** der Nutzer ein negatives Gewicht oder eine nicht ganzzahlige Wiederholungszahl eingibt
- **THEN** wird das Feld als fehlerhaft markiert, der zuletzt gültige Wert bleibt gespeichert und es entsteht keine Outbox-Mutation mit dem ungültigen Wert

#### Scenario: Prozessabbruch nach Eingabe
- **GIVEN** der Nutzer hat 8 Wiederholungen eingetragen und die App bestätigt die Speicherung
- **WHEN** das Betriebssystem die App sofort danach beendet
- **THEN** ist der Wert nach dem Neustart vorhanden

### Requirement: Erfassungsregel je Übungstyp

Ein Satz MUST als erfasst gelten, wenn alle Pflichtfelder seines Übungstyps gesetzt sind: Kraft und assistiert benötigen Gewicht und Wiederholungen, Körpergewicht mit Zusatzlast nur Wiederholungen, reines Körpergewicht nur Wiederholungen. Eine Übung gilt als vollständig, wenn alle ihre Sätze erfasst sind.

#### Scenario: Übung vollständig
- **GIVEN** eine Kraftübung mit drei Sätzen, von denen zwei Gewicht und Wiederholungen enthalten
- **WHEN** der Nutzer auch im dritten Satz beide Werte einträgt
- **THEN** wird die Übung als vollständig dargestellt

#### Scenario: Blasse Vorwerte zählen nicht
- **GIVEN** ein Satz, der nur blasse Vorwerte als Platzhalter zeigt
- **WHEN** die Vollständigkeit geprüft wird
- **THEN** gilt der Satz als nicht erfasst

#### Scenario: Klimmzug ohne Zusatzgewicht
- **GIVEN** eine Übung vom Typ Körpergewicht mit Zusatzlast
- **WHEN** der Nutzer nur 10 Wiederholungen ohne Gewicht einträgt
- **THEN** gilt der Satz als erfasst mit Zusatzgewicht 0

### Requirement: Satztypen und Nummerierung

Ein Satz SHALL genau einen Typ besitzen: normal, Aufwärmsatz oder Dropsatz. Nur normale Sätze werden fortlaufend nummeriert; Aufwärmsätze werden mit „W“ und Dropsätze mit „D“ gekennzeichnet. Unbekannte Typen aus dem Sync MUST als normal interpretiert werden.

#### Scenario: Nummerierung
- **GIVEN** die Satzfolge Aufwärmsatz, normal, Dropsatz, normal
- **WHEN** die Satzbeschriftungen berechnet werden
- **THEN** lauten sie W, 1, D, 2

### Requirement: Sätze hinzufügen, kopieren, entfernen und umordnen

Der Nutzer SHALL Sätze hinzufügen, einen Satz duplizieren, Sätze entfernen und Sätze innerhalb eines Blocks umordnen können. Ein neuer Satz übernimmt den Typ des vorherigen Satzes. Ein Duplikat erhält eine neue ID und die Werte des Originals direkt dahinter.

#### Scenario: Satz duplizieren
- **GIVEN** ein Satz 50 kg × 10
- **WHEN** der Nutzer ihn dupliziert
- **THEN** folgt direkt dahinter ein neuer Satz mit eigener ID und 50 kg × 10

#### Scenario: Letzten Satz entfernen
- **GIVEN** ein Block mit genau einem Satz
- **WHEN** der Nutzer diesen Satz entfernt
- **THEN** bleibt der Block ohne Sätze bestehen und kann über „Satz hinzufügen“ wieder befüllt werden

### Requirement: Übungen umordnen, ersetzen und entfernen

Der Nutzer SHALL Blöcke in einer eigenen Ansicht per Ziehgriff umordnen und dort entfernen können. Über das Blockmenü kann eine Übung durch eine andere ersetzt werden; erfasste Satzwerte bleiben dabei erhalten.

#### Scenario: Reihenfolge ändern
- **GIVEN** die Blöcke Bankdrücken, Rudern, Kniebeuge
- **WHEN** der Nutzer Kniebeuge an die erste Position zieht und bestätigt
- **THEN** lautet die gespeicherte Reihenfolge Kniebeuge, Bankdrücken, Rudern

#### Scenario: Übung ersetzen
- **GIVEN** ein Block „Langhantel-Bankdrücken“ mit zwei erfassten Sätzen
- **WHEN** der Nutzer die Übung durch „Kurzhantel-Bankdrücken“ ersetzt
- **THEN** zeigt der Block die neue Übung mit denselben zwei Satzwerten und die Vorwerte beziehen sich auf die neue Übung

### Requirement: Notizen auf mehreren Ebenen

Das System MUST Notizen getrennt je Training, je Übungsblock und je Satz speichern. Eine Übungsstammnotiz aus dem Katalog SHALL im Block nur lesend angezeigt werden.

#### Scenario: Blocknotiz bleibt lokal
- **GIVEN** eine Übung mit Stammnotiz „Griff schulterbreit“
- **WHEN** der Nutzer im Training die Blocknotiz „Schulter zwickt“ einträgt
- **THEN** ändert sich nur die Blocknotiz dieses Trainings, nicht die Stammnotiz der Übung

### Requirement: Optionales RIR

RIR je Satz SHALL nur angezeigt werden, wenn der Nutzer es in den Trainingseinstellungen aktiviert; Standard ist aus. RIR MUST zwischen 0 und 10 liegen und ist nie Pflichtfeld. Bereits gespeicherte RIR-Werte bleiben beim Ausblenden erhalten.

#### Scenario: RIR ausgeblendet
- **GIVEN** die RIR-Einstellung ist aus und ein Satz besitzt RIR 2
- **WHEN** der Nutzer das Training öffnet
- **THEN** wird keine RIR-Spalte angezeigt und der Wert 2 bleibt gespeichert

### Requirement: Gewichtseinheit

Der Nutzer SHALL kg oder lbs als Anzeigeeinheit wählen. Gewichte MUST kanonisch in kg gespeichert und mit dem Faktor 2,20462 umgerechnet werden. Eingaben gelten in der aktuell gewählten Einheit.

#### Scenario: Eingabe in lbs
- **GIVEN** die Anzeigeeinheit ist lbs
- **WHEN** der Nutzer 225 eingibt
- **THEN** werden etwa 102,06 kg gespeichert und weiterhin 225 lbs angezeigt

### Requirement: Vorwerte als Platzhalter

Leere Satzfelder SHALL den positionsgleichen Satz desselben Satztyps der Vorwertquelle als blassen Platzhalter zeigen, visuell klar von eingetragenen Werten unterschieden. Platzhalter MUST NOT gespeichert werden, solange der Nutzer sie nicht einträgt oder beim Beenden übernimmt.

#### Scenario: Platzhalter anzeigen
- **GIVEN** das letzte Training mit Bankdrücken enthielt 100 kg × 8 und 100 kg × 7
- **WHEN** ein neues Training mit zwei leeren Bankdrück-Sätzen geöffnet wird
- **THEN** zeigen die Sätze blass 100 × 8 und 100 × 7, ihre gespeicherten Werte bleiben leer

#### Scenario: Platzhalter per Tipp übernehmen
- **GIVEN** ein Satz zeigt blass 100 × 8
- **WHEN** der Nutzer auf die Satznummer tippt
- **THEN** werden 100 kg und 8 Wiederholungen als eigene Werte gespeichert

#### Scenario: Keine Vorwerte vorhanden
- **GIVEN** die Übung wurde noch nie trainiert
- **WHEN** der Satz angezeigt wird
- **THEN** bleiben die Felder ohne Platzhalter leer und es wird kein geschätzter Wert angezeigt

### Requirement: Vorwertquelle

Jedes Training SHALL eine Vorwertquelle besitzen: „nach Übung“ (Standard), „nach Plan“ oder „nach Training“. Die Suche MUST nur nicht gelöschte eigene Trainings mit Start vor dem aktuellen Training berücksichtigen, neuestes zuerst, und bei Kraftübungen nur Blöcke mit mindestens einem Satz mit Wiederholungen größer 0.

#### Scenario: Nach Plan mit Fallback
- **GIVEN** ein aus Plan „Push“ gestartetes Training mit Quelle „nach Plan“ und keine frühere Einheit von „Push“ mit Seitheben
- **WHEN** Vorwerte für Seitheben ermittelt werden
- **THEN** stammen sie aus dem jüngsten geeigneten Training mit Seitheben unabhängig vom Plan

#### Scenario: Leere Blöcke überspringen
- **GIVEN** das jüngste Training mit Kniebeuge enthält nur leere Sätze und das davor 120 kg × 5
- **WHEN** Vorwerte nach Übung ermittelt werden
- **THEN** zeigt der Platzhalter 120 × 5

#### Scenario: Fremde Daten
- **GIVEN** Nutzer B hat dieselbe Basisübung trainiert, Nutzer A nie
- **WHEN** Nutzer A Vorwerte abruft
- **THEN** werden keine Werte von Nutzer B angezeigt

### Requirement: Übungsverlauf im Training

Aus einem Block heraus SHALL der Nutzer den Verlauf der Übung öffnen können: frühere Trainings mit ihren erfassten Sätzen, neuestes zuerst. Vollständig leere Sätze werden ausgeblendet.

#### Scenario: Verlauf aus dem Block
- **GIVEN** zwei frühere Trainings mit Rudern, davon eines mit einem leeren und einem Satz 60 kg × 10
- **WHEN** der Nutzer im Rudern-Block den Verlauf öffnet
- **THEN** erscheinen beide Trainings neuestes zuerst und nur der Satz 60 kg × 10 wird für das betreffende Training angezeigt

### Requirement: Aufwärmhinweis anzeigen

Im aktiven Training SHALL jede Übung mit einem Vorwert-Gewicht für den ersten Arbeitssatz einen Aufwärmhinweis mit den gerundeten Gewichten der Aufwärmstufen zeigen. Ohne Vorwert-Gewicht, bei abgeschaltetem Hinweis oder bereits erfassten Aufwärmsätzen MUST der Hinweis fehlen. Der Hinweis MUST NOT gespeichert werden.

#### Scenario: Standardstufen
- **GIVEN** Standardstufen 50 % und 80 %, Rundung 2,5 kg und ein Vorwert von 80 kg im ersten Arbeitssatz
- **WHEN** die Übung im aktiven Training erscheint
- **THEN** zeigt sie „Aufwärmen 40 kg · 65 kg“

#### Scenario: Kein Vorwert
- **GIVEN** eine Übung ohne bisheriges Gewicht
- **WHEN** sie im aktiven Training erscheint
- **THEN** gibt es keinen Aufwärmhinweis

### Requirement: Einstellungen global und pro Übung

Der Nutzer SHALL den Hinweis global ein- und ausschalten, Standardstufen mit optionalen Wiederholungen festlegen und die Anzeige der Wiederholungen schalten können. Pro Übung SHALL er eigene Stufen und eine eigene Rundung setzen oder den Hinweis abschalten können. Standard MUST „Hinweis an, Wiederholungen aus, 50 % und 80 %, Rundung 2,5 kg“ sein.

#### Scenario: Übung abgeschaltet
- **GIVEN** der Hinweis ist global an, für „Bizepscurls“ aber aus
- **WHEN** „Bizepscurls“ im aktiven Training erscheint
- **THEN** fehlt dort der Hinweis, bei anderen Übungen bleibt er

#### Scenario: Wiederholungen anzeigen
- **GIVEN** Stufen 50 % × 8 und 80 % × 3, „Wiederholungen anzeigen“ ist an, Vorwert 100 kg
- **WHEN** die Übung erscheint
- **THEN** zeigt der Hinweis „50 kg × 8 · 80 kg × 3“

### Requirement: Als Aufwärmsätze eintragen

Ein Tipp auf den Hinweis SHALL anbieten, die Stufen als erfasste Aufwärmsätze vor dem ersten Arbeitssatz anzulegen.

#### Scenario: Eintragen
- **GIVEN** der Hinweis „40 kg · 65 kg“
- **WHEN** der Nutzer ihn antippt und „Als Aufwärmsätze eintragen“ wählt
- **THEN** stehen zwei Aufwärmsätze mit 40 kg und 65 kg vor dem ersten Arbeitssatz und der Hinweis verschwindet

### Requirement: Tagebuchansicht

Das Tagebuch SHALL unter einem großen Titel je Monat eine Kopfzeile mit Monat links und Trainingsanzahl rechts zeigen. Jedes Training ist eine Zeile in einer Monatskarte mit Datums-Badge (Wochentag klein, Tag groß) links, Titel und Dauer in Minuten rechts sowie darunter je Übung „<Satzanzahl>x <Übungsname>“. Oben stehen „Bearbeiten“ und „+“.

#### Scenario: Trainingszeile
- **GIVEN** ein Training „Legs 2“ am Donnerstag, 15. Oktober, mit 129 Minuten Dauer, 2 Sätzen Beinbeuger und 3 Sätzen Beinstrecker
- **WHEN** das Tagebuch angezeigt wird
- **THEN** zeigt die Zeile „Do 15“, „Legs 2“, „129 min“, „2x Beinbeuger“ und „3x Beinstrecker“

#### Scenario: Wischen zum Löschen
- **GIVEN** eine Trainingszeile im Tagebuch
- **WHEN** der Nutzer sie nach links wischt
- **THEN** erscheint eine rote Löschaktion, die erst nach Bestätigung löscht

### Requirement: Kopf des Trainingsscreens

Ein aktives Training SHALL oben links einen Minimieren-Button, daneben die Akzent-Pille „Beenden“, mittig das Datum und rechts eine gemeinsame Pille mit Timer- und Menü-Button zeigen. Ein historisches Training zeigt statt Minimieren/Beenden einen runden Akzent-Haken zum Schließen.

#### Scenario: Historisches Training öffnen
- **GIVEN** ein abgeschlossenes Training vom 15. Oktober
- **WHEN** der Nutzer es im Tagebuch öffnet
- **THEN** zeigt der Kopf einen runden türkisen Haken, „15. Okt.“ und die Timer-/Menü-Pille, aber keine „Beenden“-Pille

### Requirement: Metadatenkarte

Oberhalb der Übungen SHALL eine Karte mit dem Trainingstitel als Überschrift sowie Zeilen „Startzeit“, „Endzeit“ (Werte rechts in Sekundärtext) und „Notizen“ mit Pfeil stehen. Antippen einer Zeit öffnet einen Datums-/Zeitwähler.

#### Scenario: Startzeit ändern
- **GIVEN** die Metadatenkarte eines Trainings
- **WHEN** der Nutzer „Startzeit“ antippt und eine neue Zeit wählt
- **THEN** zeigt die Zeile den neuen Wert und die Trainingsdauer im Tagebuch passt sich an

### Requirement: Übungskarte

Jeder Übungsblock SHALL eine Karte sein mit Übungsname (fett), darunter der Übungsnotiz in kleinem Sekundärtext, rechts einem „…“-Menü, den Satzzeilen und einer Fußzeile mit „+ Satz hinzufügen“ links sowie Icon-Buttons für Verlauf, Graph und Rekorde rechts. Supersets werden als zusammenhängende Karte mit Buchstabenkennung A/B dargestellt.

#### Scenario: Fußzeilenaktionen
- **GIVEN** eine Übungskarte „Beinbeuger“
- **WHEN** der Nutzer das Rekord-Icon antippt
- **THEN** öffnen sich die persönlichen Rekorde von „Beinbeuger“ in einem Sheet

### Requirement: Satzzeile

Eine Satzzeile SHALL links das Satzlabel in einem Kreis (Nummer, W oder D), dann die Spalten mit kleinen grauen Labels „Kg“, „Wdh.“ und „Notizen“ über den Werten sowie rechts ein „…“-Menü zeigen. Spalten richten sich nach dem Übungstyp. Platzhalter-Vorwerte erscheinen deutlich blasser als eingetragene Werte.

#### Scenario: Zeile mit Vorwert und Eintrag
- **GIVEN** Satz 1 ist mit 20 kg × 6 eingetragen, Satz 2 zeigt den Vorwert 15 × 7
- **WHEN** die Übungskarte angezeigt wird
- **THEN** erscheinen 20 und 6 in Primärtext, 15 und 7 deutlich blasser, und beide Zeilen tragen die Labels Kg, Wdh. und Notizen

#### Scenario: Reines Körpergewicht
- **GIVEN** eine Übung vom Typ reines Körpergewicht
- **WHEN** ihre Satzzeile angezeigt wird
- **THEN** fehlt die Spalte „Kg“ und „Wdh.“ rückt nach links

### Requirement: Zahleneingabe mit Navigationsleiste

Beim Fokus auf ein Zahlenfeld SHALL über der Ziffernblock-Tastatur eine Leiste mit „zurück“, „weiter“ und „fertig“ sowie einem Button zum Ausblenden der Tastatur erscheinen. „Weiter“ springt von Kg zu Wdh. und von Wdh. zum Kg-Feld des nächsten Satzes. Darüber bleibt die kompakte Timerleiste sichtbar.

#### Scenario: Durch Sätze navigieren
- **GIVEN** das Wdh.-Feld von Satz 1 ist fokussiert und 6 ist eingetragen
- **WHEN** der Nutzer „weiter“ tippt
- **THEN** wird das Kg-Feld von Satz 2 fokussiert und der Wert 6 ist gespeichert

### Requirement: Übungsauswahl

Die Übungsauswahl SHALL als Sheet mit „Abbrechen“, Titel, „+“ (neue Übung) und „…“ oben, einem Suchfeld und einer Kategorienliste mit Pfeilen erscheinen. Unten steht ein Umschalter „Normal | Supersatz“; im Supersatz-Modus sind mehrere Übungen markierbar.

#### Scenario: Supersatz wählen
- **GIVEN** die Übungsauswahl im Modus „Supersatz“
- **WHEN** der Nutzer in der Kategorie „Bizeps“ und „Trizeps“ je eine Übung markiert und bestätigt
- **THEN** werden beide Übungen als Superset hinzugefügt

### Requirement: Fehlwerte-Dialog und Zusammenfassung

Der Fehlwerte-Dialog SHALL den Titel „Gewicht oder Wiederholungen fehlen“, eine Erklärung und die gestapelten Aktionen „Ja, Vorwerte verwenden“, „Trotzdem beenden“, „Weitertrainieren“ zeigen. Die Zusammenfassung zeigt eine Illustration, einen motivierenden Titel, „Dein n. Training · m. diese Woche“, eine Karte mit Volumen, Sätzen, Wiederholungen und bestem Satz je Übung sowie „Noch nicht fertig? Training fortsetzen“.

#### Scenario: Zusammenfassung
- **GIVEN** das 248. Training des Nutzers, das 4. in dieser Woche, wurde gerade beendet
- **WHEN** die Zusammenfassung erscheint
- **THEN** zeigt sie „Dein 248. Training · 4. diese Woche“ und über „Noch nicht fertig? Training fortsetzen“ kann das Training wieder geöffnet werden, wobei die Endzeit entfernt wird

### Requirement: Plan- und Wiederholen-Ansichten

Der Planeditor SHALL einen großen Titel, darunter eine Karte „Training beginnen“, eine Karte mit Name, Vorwertquelle und Notizen, je eine Karte pro Eintrag mit Satzanzahl und „+ Übung hinzufügen“ zeigen. „Training wiederholen“ ist ein Sheet mit „Training beginnen“ und den drei erklärten Vorwertquellen mit Haken an der gewählten.

#### Scenario: Vorwertquelle beim Wiederholen
- **GIVEN** das Sheet „Training wiederholen“ für ein Training vom 9. Oktober
- **WHEN** der Nutzer „Wiederholtes Training“ wählt und „Training beginnen“ tippt
- **THEN** startet ein neues Training, dessen Platzhalter die Werte vom 9. Oktober zeigen
