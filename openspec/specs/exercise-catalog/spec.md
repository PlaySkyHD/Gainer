# exercise-catalog Specification

## Purpose
Übungskatalog aus unveränderlichen deutschen Basisübungen und eigenen Übungen mit Übungstyp, Kategorien, Muskeln, Rechenfaktoren, Suche, Archivierung, Zusammenführen und Muskelübersicht.

## Requirements

### Requirement: Übungstypen

Jede Übung MUST genau einen Übungstyp besitzen. In dieser Phase SHALL das System die Typen Kraft (Gewicht × Wiederholungen), Körpergewicht mit Zusatzlast, reines Körpergewicht und assistiert (Unterstützungsgewicht × Wiederholungen) anbieten. Unbekannte Typen aus dem Sync MUST abgelehnt und nicht still umgedeutet werden.

#### Scenario: Eingabefelder nach Typ
- **GIVEN** eine Übung vom Typ reines Körpergewicht
- **WHEN** sie in einem Training angezeigt wird
- **THEN** enthält die Satzzeile nur ein Wiederholungsfeld und kein Gewichtsfeld

#### Scenario: Assistiertes Gewicht
- **GIVEN** eine assistierte Klimmzugübung
- **WHEN** der Nutzer 20 kg Unterstützung und 8 Wiederholungen einträgt
- **THEN** wird der Satz als 20 kg Unterstützung angezeigt und in Kennzahlen als Entlastung vom Körpergewicht behandelt

### Requirement: Basiskatalog

Das System MUST einen nur lesbaren Basiskatalog mit stabilen IDs, Typ, Kategorien, Muskelgruppen, Equipment und Faktoren bereitstellen. Basisübungen DÜRFEN durch Nutzer nicht verändert oder archiviert werden.

#### Scenario: Basisübung ändern
- **GIVEN** ein Nutzer kennt die ID einer Basisübung
- **WHEN** er versucht, sie umzubenennen oder zu archivieren
- **THEN** wird die Änderung abgelehnt und die Basisübung bleibt unverändert

### Requirement: Eigene Übungen

Der Nutzer SHALL eigene Übungen mit Name (1–160 Zeichen), Typ, Kategorien, Notiz sowie optionalem Körpergewichts- und Zusatzgewichtsfaktor anlegen, bearbeiten und archivieren können. Eigene Übungen MUST nur für ihren Eigentümer sichtbar sein.

#### Scenario: Eigene Übung offline anlegen
- **GIVEN** das Gerät ist offline
- **WHEN** der Nutzer die Übung „Landmine Press“ vom Typ Kraft anlegt
- **THEN** ist sie sofort mit stabiler ID lokal auswählbar und wird später synchronisiert

#### Scenario: Typ einer verwendeten Übung ändern
- **GIVEN** eine eigene Übung mit erfassten Sätzen in früheren Trainings
- **WHEN** der Nutzer ihren Typ ändert
- **THEN** warnt die App, dass bestehende Sätze nach dem neuen Typ ausgewertet werden, und speichert erst nach Bestätigung

#### Scenario: Archivierte Übung in der Historie
- **GIVEN** eine eigene Übung wird in früheren Trainings und einem Plan verwendet
- **WHEN** der Nutzer sie archiviert
- **THEN** wird sie für neue Trainings nicht mehr angeboten, bleibt aber in Historie, Plan und Statistiken auflösbar

### Requirement: Kategorien

Das System SHALL Basis-Kategorien (z. B. Brust, Rücken, Beine) und eigene Kategorien bereitstellen. Eine Übung kann mehreren Kategorien angehören. Der Nutzer kann eigene Kategorien anlegen, umbenennen und archivieren; Basis-Kategorien sind unveränderlich.

#### Scenario: Eigene Kategorie archivieren
- **GIVEN** eine eigene Kategorie „Reha“ mit zwei zugeordneten Übungen
- **WHEN** der Nutzer die Kategorie archiviert
- **THEN** verschwindet sie aus der Auswahl und die beiden Übungen bleiben unverändert erhalten

### Requirement: Übungsauswahl und Suche

Die Übungsauswahl SHALL nicht archivierte Basis- und eigene Übungen alphabetisch anzeigen, nach Kategorie filtern und nach Namen unabhängig von Groß-/Kleinschreibung und Umlautschreibweise durchsuchen. Zuletzt verwendete Übungen werden zuerst angeboten.

#### Scenario: Suche
- **GIVEN** die Übungen „Kniebeuge“ und „Bulgarische Kniebeuge“
- **WHEN** der Nutzer „kniebeu“ eingibt
- **THEN** erscheinen beide Übungen in den Treffern

#### Scenario: Mehrfachauswahl
- **GIVEN** die Übungsauswahl ist aus einem Training geöffnet
- **WHEN** der Nutzer zwei Übungen markiert und „Als Superset hinzufügen“ wählt
- **THEN** werden beide Übungen als Superset in das Training übernommen

### Requirement: Rechenfaktoren

Jede Übung SHALL einen Körpergewichtsfaktor (Anteil des Körpergewichts, 0–100 %) und einen Zusatzgewichtsfaktor besitzen. Ein eigener Faktor hat Vorrang vor dem Katalogwert; ohne beides gilt 0 % Körpergewicht bei Krafttypen, 100 % bei Körpergewichtstypen und Zusatzgewichtsfaktor 1.

#### Scenario: Liegestütz mit Faktor
- **GIVEN** Liegestütz besitzt den Körpergewichtsfaktor 64 % und das maßgebliche Körpergewicht aus dem Check-in beträgt 80 kg
- **WHEN** das Volumen eines Satzes mit 10 Wiederholungen berechnet wird
- **THEN** beträgt es 512 kg

### Requirement: Übungen zusammenführen

Der Nutzer SHALL eine eigene Übung in eine andere eigene oder Basis-Übung zusammenführen können. Danach MUST alle Trainingsblöcke und Planeinträge des Nutzers auf die Zielübung verweisen und die Quellübung archiviert sein. Gespeicherte Übungsnamen in historischen Trainings bleiben erhalten.

#### Scenario: Doppelte Übung zusammenführen
- **GIVEN** die eigene Übung „Bankdrücken LH“ wird in zwei Trainings und einem Plan verwendet
- **WHEN** der Nutzer sie in die Basisübung „Bankdrücken“ zusammenführt
- **THEN** zählen beide Trainings für Verlauf, Vorwerte und Rekorde von „Bankdrücken“, der Plan verweist auf „Bankdrücken“ und „Bankdrücken LH“ ist archiviert

#### Scenario: Zusammenführen offline wiederholt
- **GIVEN** eine Zusammenführung wurde offline ausgeführt und ihre Sync-Mutation wird nach Netzwerkabbruch erneut gesendet
- **WHEN** das Backend sie verarbeitet
- **THEN** wird sie genau einmal angewendet

#### Scenario: Fremde Zielübung
- **GIVEN** Nutzer A gibt die ID einer eigenen Übung von Nutzer B als Ziel an
- **WHEN** das Backend die Zusammenführung verarbeitet
- **THEN** wird sie ohne Änderung und ohne Datenoffenlegung abgelehnt

### Requirement: Deutscher Basiskatalog

Der Basiskatalog SHALL gängige Übungen mit deutschem Namen, Equipment, Kategorien, mindestens einem Hauptmuskel und einer kurzen Anleitung enthalten. Bestehende Basisübungen MUST ihre IDs behalten.

#### Scenario: Basisübung ansehen
- **GIVEN** die Basisübung „Bankdrücken (Langhantel)“
- **WHEN** der Nutzer sie im Katalog öffnet
- **THEN** sieht er Equipment „Langhantel“, eine Anleitung und Brust als Hauptmuskel

#### Scenario: Bisherige Übung
- **GIVEN** ein Training mit der früheren Basisübung „Barbell Bench Press“
- **WHEN** der neue Katalog ausgeliefert ist
- **THEN** zeigt der Katalog dieselbe Übung als „Bankdrücken (Langhantel)“ und das Training behält seinen Namen

### Requirement: Muskel-Vorschlag beim Anlegen

Solange eine eigene Übung keine Muskeln hat, SHALL der Editor die Muskeln der Übung mit dem ähnlichsten Namen vorschlagen. Equipment allein MUST NOT zu einem Vorschlag führen.

#### Scenario: Vorschlag übernehmen
- **GIVEN** der Katalog enthält „Schrägbankdrücken (Kurzhantel)“
- **WHEN** der Nutzer eine neue Übung „schraegbankdruecken kh“ benennt und „Übernehmen“ tippt
- **THEN** stehen Brust als Haupt- sowie vordere Schulter und Trizeps als Hilfsmuskeln im Editor

#### Scenario: Kein Vorschlag
- **GIVEN** der Name „Kurzhantel“
- **WHEN** der Editor einen Vorschlag sucht
- **THEN** erscheint keiner

### Requirement: Muskeln einer Übung

Jede Übung SHALL bis zu 3 Hauptmuskeln und bis zu 6 Hilfsmuskeln aus einer festen Liste von 17 Regionen haben können. Ein Muskel MUST NOT gleichzeitig Haupt- und Hilfsmuskel derselben Übung sein. Eigene Übungen SHALL im Übungseditor bearbeitbar sein, Basisübungen MUST ihre Katalogwerte nur anzeigen. Das Backend MUST unbekannte Schlüssel, Wiederholungen und Überschneidungen ablehnen.

#### Scenario: Muskeln wählen
- **GIVEN** eine eigene Übung „Schrägbankdrücken“ ohne Muskeln
- **WHEN** der Nutzer Brust als Hauptmuskel sowie Trizeps und vordere Schulter als Hilfsmuskeln wählt und speichert
- **THEN** zeigt der Editor die Brust voll und Trizeps und vordere Schulter halb eingefärbt, und die Werte werden synchronisiert

#### Scenario: Überschneidung gesperrt
- **GIVEN** Brust ist Hauptmuskel
- **WHEN** der Nutzer die Hilfsmuskeln auswählt
- **THEN** ist Brust dort gesperrt und als „Hauptmuskel“ beschriftet

### Requirement: Sätze je Muskel

Die App SHALL je Muskel die Arbeitssätze zählen. Ein Hauptmuskel zählt 1 je Arbeitssatz, ein Hilfsmuskel 0,5. Aufwärmsätze MUST NOT zählen.

#### Scenario: Geplante Sätze
- **GIVEN** ein Plan mit Bankdrücken (Haupt Brust, Hilfs Trizeps) mit 4 Arbeitssätzen und Trizepsdrücken (Haupt Trizeps) mit 3 Arbeitssätzen
- **WHEN** die Muskelübersicht diesen Plan zeigt
- **THEN** stehen bei Brust 4 Sätze und bei Trizeps 5 Sätze

#### Scenario: Trainierte Sätze
- **GIVEN** zwei abgeschlossene Trainings in den letzten 7 Tagen mit je 2 Aufwärm- und 3 Arbeitssätzen Kniebeugen (Haupt Quadrizeps)
- **WHEN** die Übersicht „Trainiert, 7 Tage“ zeigt
- **THEN** stehen bei Quadrizeps 6 Sätze

### Requirement: Muskelübersicht

Die App SHALL eine Körperkarte mit Vorder- und Rückansicht zeigen, deren Farbstufen der Satzzahl je Muskel folgen. Die Übersicht SHALL zwischen „Geplant“ (alle aktiven Pläne oder ein einzelner Plan) und „Trainiert“ (letzte 7 Tage oder Ø pro Woche der letzten 28 Tage) umschalten. Übungen ohne Muskelangabe MUST als Hinweis genannt werden.

#### Scenario: Gesamtbild aller Pläne
- **GIVEN** die aktiven Pläne „Push“ und „Pull“ trainieren keine Beine
- **WHEN** der Nutzer „Geplant, Alle Pläne“ öffnet
- **THEN** sind Quadrizeps, Beinbeuger, Gesäß und Waden grau und stehen mit 0 Sätzen in der Liste

#### Scenario: Ein Plan
- **GIVEN** die Übersicht zeigt alle Pläne
- **WHEN** der Nutzer unter „Plan“ den Plan „Pull“ wählt
- **THEN** zeigt Karte und Liste nur die Sätze aus „Pull“

#### Scenario: Muskel antippen
- **GIVEN** die Übersicht zeigt Brust mit 8 Sätzen
- **WHEN** der Nutzer auf die Brust tippt
- **THEN** listet ein Sheet die beitragenden Übungen mit ihren Sätzen und ob die Brust dort Haupt- oder Hilfsmuskel ist

### Requirement: Muskeln im Plan-Editor

Der Plan-Editor SHALL eine Körperkarte des Plans zeigen, sobald er eine Übung enthält. Sie MUST dem aktuellen, auch ungespeicherten Stand folgen.

#### Scenario: Übung hinzufügen
- **GIVEN** ein Plan mit nur Bankdrücken
- **WHEN** der Nutzer Klimmzüge hinzufügt
- **THEN** färbt die Karte sofort zusätzlich den Latissimus ein

### Requirement: Muskeln nachtragen

Die App SHALL den Übungseditor aus dem Übungsmenü eines Trainings und aus der Liste „Ohne Muskeln“ der Muskelübersicht öffnen. Übungen, die nicht im Katalog bekannt sind, MUST NOT einen Editor anbieten.

#### Scenario: Aus dem Training
- **GIVEN** ein aktives Training mit der eigenen Übung „Schrägbankdrücken“
- **WHEN** der Nutzer im Übungsmenü „Übung bearbeiten“ wählt
- **THEN** öffnet sich der Übungseditor mit dem Abschnitt „Muskeln“

#### Scenario: Aus der Übersicht
- **GIVEN** die Übersicht listet „Curls“ unter „Ohne Muskeln“
- **WHEN** der Nutzer „Curls“ antippt, Bizeps als Hauptmuskel wählt und speichert
- **THEN** fehlt „Curls“ in der Gruppe und die Karte zählt die Sätze beim Bizeps

### Requirement: Muskeln im Dialog mit der KI ermitteln

Der Übungseditor SHALL für bearbeitbare Übungen mit Namen „Mit KI ermitteln“ anbieten. Die KI SHALL entweder höchstens zwei Rückfragen mit Antwort-Optionen stellen oder Haupt- und Hilfsmuskeln aus den 17 Muskel-Schlüsseln mit kurzer Begründung vorschlagen. Ein Vorschlag MUST erst nach „Übernehmen“ in den Editor gelangen und MUST NOT automatisch gespeichert werden.

#### Scenario: Rückfrage und Vorschlag
- **GIVEN** eine eigene Übung „Rudern Maschine“
- **WHEN** der Nutzer „Mit KI ermitteln“ tippt, die KI nach dem Griff fragt und er „Eng“ wählt
- **THEN** zeigt das Sheet einen Vorschlag auf der Körperkarte, und nach „Übernehmen“ stehen die Muskeln im Editor

#### Scenario: Höchstens zwei Rückfragen
- **GIVEN** zwei beantwortete Rückfragen
- **WHEN** die App erneut anfragt
- **THEN** antwortet der Server nur mit einem Vorschlag oder einem Fehler

### Requirement: Kontingent und Fehler

Der Server SHALL KI-Anfragen pro Nutzer und Tag begrenzen und bei Überschreitung 429 mit `daily_budget_exhausted` antworten. Die App MUST Fehler verständlich anzeigen und einen erneuten Versuch anbieten.

#### Scenario: Tageslimit
- **GIVEN** das Tageslimit ist erreicht
- **WHEN** der Nutzer „Mit KI ermitteln“ tippt
- **THEN** zeigt das Sheet „Das Tageslimit für KI-Anfragen ist erreicht. Morgen geht es wieder.“
