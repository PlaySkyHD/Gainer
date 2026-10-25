## ADDED Requirements

### Requirement: Wassermenge pro Tag

Das System SHALL pro Nutzer und lokalem Kalendertag höchstens eine getrunkene Wassermenge in ganzen Millilitern speichern. Die Menge MUST zwischen 0 und 10.000 ml liegen. „Menge hinzufügen“ MUST mindestens 1 ml addieren und DARF die Obergrenze nicht überschreiten. „Tagesmenge setzen“ SHALL jeden Wert von 0 bis 10.000 ml erlauben. Beide Änderungen MUST die Basisversion prüfen und die Version erhöhen. Ein Tag mit 0 ml SHALL als Stand erhalten bleiben.

#### Scenario: Erstes Glas des Tages

- **GIVEN** für den 25.10.2026 ist noch keine Wassermenge gespeichert
- **WHEN** der Nutzer 300 ml hinzufügt
- **THEN** speichert das System für diesen Tag 300 ml mit Version 1

#### Scenario: Weitere Menge hinzufügen

- **GIVEN** für den Tag sind 1.250 ml mit Version 3 gespeichert
- **WHEN** eine Mutation mit Basisversion 3 weitere 500 ml hinzufügt
- **THEN** beträgt die Tagesmenge 1.750 ml mit Version 4

#### Scenario: Obergrenze

- **GIVEN** für den Tag sind 9.800 ml gespeichert
- **WHEN** eine Mutation 300 ml hinzufügen oder die Menge auf 10.001 ml setzen will
- **THEN** lehnt der Server sie als ungültig ab und die Menge bleibt 9.800 ml

#### Scenario: Auf 0 ml zurücksetzen

- **GIVEN** für den Tag sind 800 ml gespeichert
- **WHEN** der Nutzer die Tagesmenge auf 0 ml setzt
- **THEN** speichert das System 0 ml als neue Version und überträgt keinen Löschvorgang

#### Scenario: Veraltete Basisversion

- **GIVEN** die Wassermenge des Tages hat auf dem Server Version 4
- **WHEN** eine Mutation mit Basisversion 3 eintrifft
- **THEN** antwortet der Server mit `stale_base_version` und ändert die Menge nicht

### Requirement: Wassermenge synchronisieren

Die App MUST jede Änderung der Wassermenge atomar mit Mutation-ID in der Outbox des Kontos speichern und offline sofort anzeigen. Wartet eine ungesendete Änderung, SHALL sie die neue Summe senden statt einer Differenz. Der Server MUST jede Änderung mit Snapshot im Change-Feed veröffentlichen, damit sie im Datenexport erscheint. Fremde Daten DÜRFEN weder lesbar noch änderbar sein.

#### Scenario: Offline mehrfach tippen

- **GIVEN** das Gerät ist offline und für heute sind 0 ml gespeichert
- **WHEN** der Nutzer nacheinander „+500 ml“, „+500 ml“ und „+300 ml“ tippt
- **THEN** zeigt die Karte sofort 1.300 ml, es wartet genau eine Änderung für den Tag, und nach dem Sync speichert der Server 1.300 ml

#### Scenario: Fremden Tag adressieren

- **GIVEN** Nutzer A kennt die ID der Wassermenge von Nutzer B
- **WHEN** Nutzer A für diese ID Wasser hinzufügt
- **THEN** behandelt der Server sie wie eine nicht vorhandene Ressource und die Menge von Nutzer B bleibt unverändert

#### Scenario: Datenexport

- **GIVEN** der Nutzer hat für zwei Tage Wasser erfasst
- **WHEN** er seine Daten exportiert
- **THEN** enthält der Export beide Tage als Ressource `WaterIntakeDay` mit ihrer aktuellen Menge

### Requirement: Wasser-Karte im Ernährungstag

Ist „Wasser erfassen“ eingeschaltet, SHALL der Ernährungstag unter der Tageskarte eine Karte „Wasser“ mit „Menge / Ziel ml“ in deutscher Zahlenformatierung, einem Fortschrittsbalken und den Schnellknöpfen „+200 ml“, „+300 ml“ und „+500 ml“ zeigen. Ein Schnellknopf, der die Obergrenze überschreiten würde, MUST deaktiviert sein. Antippen der Menge SHALL ein Sheet öffnen, in dem der Nutzer die Tagesmenge korrigieren oder auf 0 ml zurücksetzen kann. Bei Textgröße 2 DARF nichts überlaufen.

#### Scenario: Schnellknopf

- **GIVEN** „Wasser erfassen“ ist an, das Ziel ist 2.500 ml und heute sind 750 ml erfasst
- **WHEN** der Nutzer „+500 ml“ tippt
- **THEN** zeigt die Karte „1.250 / 2.500 ml“

#### Scenario: Korrigieren

- **GIVEN** die Karte zeigt „1.300 / 2.500 ml“
- **WHEN** der Nutzer die Menge antippt, 800 eingibt und sichert
- **THEN** schließt das Sheet und die Karte zeigt „800 / 2.500 ml“

#### Scenario: Ungültige Eingabe

- **GIVEN** das Sheet „Wasser“ ist offen
- **WHEN** der Nutzer 12000 eingibt
- **THEN** zeigt das Feld „Erlaubt sind 0 bis 10.000 ml.“, „Sichern“ ist gesperrt und nichts wird gespeichert

#### Scenario: Grenze erreicht

- **GIVEN** heute sind 9.800 ml erfasst
- **WHEN** der Nutzer die Karte ansieht
- **THEN** sind „+300 ml“ und „+500 ml“ deaktiviert und „+200 ml“ ist verfügbar, weil es genau 10.000 ml ergibt

### Requirement: Wasser in den Ernährungs-Einstellungen

Das Menü (…) der Ernährung SHALL den Eintrag „Einstellungen“ anbieten. Dort SHALL der Schalter „Wasser erfassen“ stehen, standardmäßig aus, und bei eingeschaltetem Schalter das Tagesziel in ml zwischen 250 und 10.000, standardmäßig 2.500 ml. Die Einstellungen MUST gerätelokal und an das angemeldete Konto gebunden gespeichert werden und DÜRFEN keine Sync-Mutation erzeugen. Ausschalten SHALL nur die Karte ausblenden und gespeicherte Mengen erhalten.

#### Scenario: Standard

- **GIVEN** ein Nutzer hat die Ernährungs-Einstellungen nie geöffnet
- **WHEN** er den Ernährungstag öffnet
- **THEN** ist keine Wasser-Karte zu sehen

#### Scenario: Einschalten mit eigenem Ziel

- **GIVEN** die Ernährungs-Einstellungen sind offen
- **WHEN** der Nutzer „Wasser erfassen“ einschaltet und als Tagesziel 3000 eingibt
- **THEN** zeigt der Ernährungstag die Karte mit „0 / 3.000 ml“

#### Scenario: Anderes Konto

- **GIVEN** Nutzer A hat auf dem Gerät „Wasser erfassen“ eingeschaltet
- **WHEN** sich Nutzer B auf demselben Gerät anmeldet
- **THEN** ist für Nutzer B die Wasser-Karte ausgeblendet
