# Spec Delta

## Purpose

Diese Capability definiert Übungsblöcke und Sätze innerhalb eines Trainings: schnelle Inline-Erfassung, Satztypen, Supersets, Reihenfolge, Gewichtseinheit und die Anzeige sowie Übernahme von Vorwerten.

## ADDED Requirements

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
