# Spec Delta

## Purpose

Diese Capability definiert den Übungskatalog aus unveränderlichen Basisübungen und nutzereigenen Übungen mit Übungstyp, Kategorien, Rechenfaktoren, Suche, Archivierung und dem Zusammenführen doppelter Übungen.

## ADDED Requirements

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
