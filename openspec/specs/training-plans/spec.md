# training-plans Specification

## Purpose
Wiederverwendbare Trainingspläne: anlegen, bearbeiten, duplizieren, ein Training aus einem Plan starten und ein Training als Plan speichern.

## Requirements

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

### Requirement: Plan duplizieren

Langes Drücken auf einen Plan in der Planliste SHALL ein Kontext-Sheet mit „Duplizieren“ öffnen. Duplizieren SHALL einen neuen Plan „<Name> Kopie“ am Ende der Liste anlegen, der Einträge, Sätze, Notizen, Supersets und Vorwerte-Quelle übernimmt, und ihn im Planeditor öffnen. Plan, Einträge und Supersets MUST neue IDs bekommen.

#### Scenario: Kopie anlegen
- **GIVEN** die Pläne „Push“ und „Pull“, „Pull“ mit einem Superset aus Latzug und Rudern
- **WHEN** der Nutzer lange auf „Pull“ drückt und „Duplizieren“ wählt
- **THEN** stehen „Push“, „Pull“ und „Pull Kopie“ in der Liste, der Planeditor zeigt „Pull Kopie“, und die Kopie enthält Latzug und Rudern als Superset mit neuer Superset-ID

#### Scenario: Langer Name
- **GIVEN** ein Plan mit 160 Zeichen langem Namen
- **WHEN** er dupliziert wird
- **THEN** ist der neue Name 160 Zeichen lang und endet auf „ Kopie“

### Requirement: Übungsmenü im Planeditor

Jeder Eintrag im Planeditor SHALL ein Übungsmenü mit Verschieben, Ersetzen, Löschen und „Sätze bearbeiten“ bieten, erreichbar über den „…“-Knopf und langes Drücken. Bei nur einem Eintrag MUST „Verschieben“ fehlen. Änderungen MUST erst mit „Speichern“ gespeichert werden.

#### Scenario: Verschieben
- **GIVEN** ein Plan mit Latzug, TBar und HighRow
- **WHEN** der Nutzer HighRow im Neuordnen-Sheet an den Anfang zieht, „Fertig“ und dann „Speichern“ tippt
- **THEN** ist die gespeicherte Reihenfolge HighRow, Latzug, TBar

#### Scenario: Ersetzen
- **GIVEN** ein Eintrag „Latzug“ mit 3 Arbeitssätzen
- **WHEN** der Nutzer „Ersetzen“ wählt, „Klimmzug“ auswählt und speichert
- **THEN** steht an derselben Stelle „Klimmzug“ mit 3 Arbeitssätzen und derselben Eintrags-ID

#### Scenario: Nur ein Eintrag
- **GIVEN** ein Plan mit genau einem Eintrag
- **WHEN** der Nutzer das Übungsmenü öffnet
- **THEN** fehlt „Verschieben“, „Ersetzen“ wird angeboten

### Requirement: Superset auflösen

Ein Superset-Eintrag, der nach Verschieben oder Löschen keinen Nachbarn desselben Supersets mehr hat, SHALL zu einer normalen Übung werden.

#### Scenario: Löschen trennt Superset
- **GIVEN** TBar und HighRow bilden ein Superset
- **WHEN** der Nutzer TBar löscht und speichert
- **THEN** ist HighRow keinem Superset mehr zugeordnet
