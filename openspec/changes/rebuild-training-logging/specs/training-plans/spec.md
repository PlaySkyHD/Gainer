# Spec Delta

## Purpose

Diese Capability definiert wiederverwendbare Trainingspläne, das Starten eines Trainings aus einem Plan, das Speichern eines Trainings als Plan und eine geordnete Rotation, die den nächsten Plan vorschlägt.

## ADDED Requirements

### Requirement: Trainingspläne verwalten

Der Nutzer SHALL eigene Pläne mit Name, Notiz, Vorwertquelle und einer geordneten Liste von Einträgen anlegen, bearbeiten, umordnen und archivieren können. Pläne werden in einer vom Nutzer festgelegten Reihenfolge angezeigt; archivierte Pläne erscheinen nicht in der Standardliste.

#### Scenario: Plan anlegen
- **GIVEN** ein Nutzer mit Basis- und eigenen Übungen
- **WHEN** er einen Plan „Push“ mit Bankdrücken und Schulterdrücken speichert
- **THEN** erhält der Plan eine stabile ID, erscheint am Ende der Planliste und ist nur für ihn sichtbar

#### Scenario: Ungültiger Plan
- **GIVEN** ein Plan ohne Namen
- **WHEN** der Nutzer speichert
- **THEN** wird das Speichern mit einem Feldfehler abgelehnt und der vorherige Stand bleibt erhalten

#### Scenario: Fremder Plan
- **GIVEN** Nutzer A kennt die Plan-ID von Nutzer B
- **WHEN** Nutzer A den Plan lesen, ändern oder daraus starten will
- **THEN** lehnt das Backend die Operation ohne Offenlegung von Inhalten ab

### Requirement: Planeinträge

Ein Planeintrag SHALL aus Übung, Anzahl Aufwärmsätze (0–20, Standard 0), Anzahl Arbeitssätze (0–50, Standard 3), Notiz und optionaler Superset-ID bestehen. Je Eintrag MUST mindestens ein und höchstens 50 Sätze insgesamt vorhanden sein. Supersets werden wie im Training über benachbarte Einträge mit gleicher ID gebildet.

#### Scenario: Neuer Eintrag mit Standardwerten
- **GIVEN** ein Plan im Editor
- **WHEN** der Nutzer „Seitheben“ hinzufügt, ohne Werte zu ändern
- **THEN** besitzt der Eintrag 0 Aufwärmsätze und 3 Arbeitssätze

#### Scenario: Eintrag ohne Sätze
- **GIVEN** ein Eintrag mit 0 Aufwärm- und 0 Arbeitssätzen
- **WHEN** der Nutzer den Plan speichert
- **THEN** wird das Speichern mit einem Feldfehler am Eintrag abgelehnt

### Requirement: Training aus Plan starten

Beim Start aus einem Plan MUST ein Training entstehen, das Planname als Titel, Plannotiz, Vorwertquelle und Planverweis übernimmt. Jeder Eintrag erzeugt einen Block mit Übung, Notiz und Superset-ID, zuerst die Aufwärmsätze, dann die Arbeitssätze als normale Sätze, alle ohne Werte.

#### Scenario: Plan starten
- **GIVEN** ein Plan mit Bankdrücken, 2 Aufwärmsätzen und 3 Arbeitssätzen
- **WHEN** der Nutzer den Plan startet
- **THEN** entsteht ein aktives Training mit einem Bankdrück-Block und den Sätzen W, W, 1, 2, 3 ohne gespeicherte Werte

#### Scenario: Plan offline starten
- **GIVEN** der Plan ist lokal vollständig vorhanden und das Gerät offline
- **WHEN** der Nutzer ihn startet
- **THEN** wird das Training sofort lokal angelegt und später synchronisiert

#### Scenario: Plan nach Start ändern
- **GIVEN** ein aus „Push“ gestartetes Training
- **WHEN** der Nutzer den Plan „Push“ danach bearbeitet
- **THEN** bleiben Blöcke und Sätze des gestarteten Trainings unverändert

### Requirement: Training als Plan speichern

Der Nutzer SHALL ein Training als Plan speichern können. Existiert ein nicht archivierter Plan mit gleichem Namen (ohne Groß-/Kleinschreibung), MUST die App fragen, ob dieser überschrieben oder ein neuer Plan angelegt wird. Aufwärmsätze werden gezählt, alle übrigen Sätze zählen als Arbeitssätze.

#### Scenario: Neuen Plan aus Training
- **GIVEN** ein Training „Beine“ mit Kniebeuge (1 Aufwärmsatz, 2 normale, 1 Dropsatz) und kein Plan „Beine“
- **WHEN** der Nutzer „Als Plan speichern“ wählt
- **THEN** entsteht ein Plan „Beine“ mit Kniebeuge, 1 Aufwärmsatz und 3 Arbeitssätzen

#### Scenario: Gleichnamigen Plan überschreiben
- **GIVEN** ein Plan „push“ existiert
- **WHEN** der Nutzer ein Training „Push“ als Plan speichert und „Überschreiben“ bestätigt
- **THEN** wird der bestehende Plan mit den Einträgen des Trainings ersetzt und kein zweiter Plan angelegt

### Requirement: Plan-Rotation

Der Nutzer SHALL Pläne in eine geordnete Rotation aufnehmen können. Das System MUST nach dem Beenden eines aus einem Rotationsplan gestarteten Trainings den nächsten aktiven Plan vorschlagen; nach dem letzten folgt der erste. Archivierte Pläne werden übersprungen; gelöschte Trainings zählen nicht.

#### Scenario: Nächster Plan
- **GIVEN** die Rotation „Push“, „Pull“, „Beine“ und zuletzt wurde ein „Push“-Training beendet
- **WHEN** der Nutzer die Trainingspläne öffnet
- **THEN** wird „Pull“ als nächstes Training hervorgehoben und lässt sich mit einem Tipp starten

#### Scenario: Letztes Training gelöscht
- **GIVEN** das zuletzt beendete Rotationstraining „Pull“ wird gelöscht und davor wurde „Push“ beendet
- **WHEN** der Vorschlag neu berechnet wird
- **THEN** wird wieder „Pull“ vorgeschlagen

#### Scenario: Leere Rotation
- **GIVEN** die Rotation enthält keinen aktiven Plan
- **WHEN** die Pläne angezeigt werden
- **THEN** wird kein Vorschlag angezeigt
