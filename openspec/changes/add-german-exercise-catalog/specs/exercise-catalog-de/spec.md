# exercise-catalog-de

## ADDED Requirements

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
