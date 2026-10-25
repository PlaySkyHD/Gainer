## MODIFIED Requirements

### Requirement: Wassermenge pro Tag

Das System SHALL pro Nutzer und lokalem Kalendertag höchstens eine getrunkene Wassermenge in ganzen Millilitern speichern, unter einer festen ID je Nutzer und Tag. Die Menge MUST zwischen 0 und 10.000 ml liegen. Jede Änderung MUST die neue Tagesmenge setzen, die Basisversion prüfen und die Version erhöhen. Ein anderes Datum für eine bekannte ID MUST als ungültig abgelehnt werden. Ein Tag mit 0 ml SHALL als Stand erhalten bleiben.

#### Scenario: Erstes Glas des Tages

- **GIVEN** für den 25.10.2026 ist noch keine Wassermenge gespeichert
- **WHEN** der Nutzer 300 ml hinzufügt
- **THEN** speichert das System für diesen Tag 300 ml mit Version 1

#### Scenario: Weitere Menge hinzufügen

- **GIVEN** für den Tag sind 1.250 ml mit Version 3 gespeichert
- **WHEN** der Nutzer weitere 500 ml hinzufügt
- **THEN** sendet die App die Summe 1.750 ml mit Basisversion 3 und der Server speichert sie mit Version 4

#### Scenario: Obergrenze

- **GIVEN** für den Tag sind 9.800 ml gespeichert
- **WHEN** eine Mutation die Menge auf 10.001 ml setzen will
- **THEN** lehnt der Server sie als ungültig ab und die Menge bleibt 9.800 ml

#### Scenario: Auf 0 ml zurücksetzen

- **GIVEN** für den Tag sind 800 ml gespeichert
- **WHEN** der Nutzer die Tagesmenge auf 0 ml setzt
- **THEN** speichert das System 0 ml als neue Version und überträgt keinen Löschvorgang

#### Scenario: Veraltete Basisversion

- **GIVEN** die Wassermenge des Tages hat auf dem Server Version 4
- **WHEN** eine Mutation mit Basisversion 3 eintrifft
- **THEN** antwortet der Server mit `stale_base_version` und ändert die Menge nicht

#### Scenario: Zwei Geräte, derselbe Tag

- **GIVEN** zwei Geräte desselben Kontos erfassen offline Wasser für den 25.10.2026
- **WHEN** beide synchronisieren
- **THEN** verwenden beide dieselbe ID, der zweite Stand wird ein lösbarer Konflikt dieser Ressource und es entsteht kein zweiter Tag

#### Scenario: Falsches Datum für eine bekannte ID

- **GIVEN** die ID eines Tages gehört zum 25.10.2026
- **WHEN** eine Mutation dieselbe ID mit dem 26.10.2026 sendet
- **THEN** antwortet der Server mit `invalid_payload` und ändert nichts

### Requirement: Wassermenge synchronisieren

Die App MUST jede Änderung der Wassermenge atomar mit Mutation-ID in der Outbox des Kontos speichern und offline sofort anzeigen. Ein Pull oder eine Bestätigung zwischen Lesen und Schreiben DARF nicht überschrieben werden. Der Server MUST jede Änderung mit Snapshot im Change-Feed veröffentlichen, damit sie im Datenexport erscheint. Fremde Daten DÜRFEN weder lesbar noch änderbar sein.

#### Scenario: Offline mehrfach tippen

- **GIVEN** das Gerät ist offline und für heute sind 0 ml gespeichert
- **WHEN** der Nutzer nacheinander „+500 ml“, „+500 ml“ und „+300 ml“ tippt
- **THEN** zeigt die Karte sofort 1.300 ml, es wartet genau eine Änderung für den Tag, und nach dem Sync speichert der Server 1.300 ml

#### Scenario: Bestätigung während des Tippens

- **GIVEN** für heute wartet 500 ml auf den Server
- **WHEN** die Bestätigung mit Version 1 genau zwischen Lesen und Schreiben eines Tipps auf „+200 ml“ eintrifft
- **THEN** liest die App neu und sendet 700 ml mit Basisversion 1

#### Scenario: Fremden Tag adressieren

- **GIVEN** Nutzer A kennt die ID der Wassermenge von Nutzer B
- **WHEN** Nutzer A für diese ID Wasser hinzufügt
- **THEN** behandelt der Server sie wie eine nicht vorhandene Ressource und die Menge von Nutzer B bleibt unverändert

#### Scenario: Datenexport

- **GIVEN** der Nutzer hat für zwei Tage Wasser erfasst
- **WHEN** er seine Daten exportiert
- **THEN** enthält der Export beide Tage als Ressource `WaterIntakeDay` mit ihrer aktuellen Menge

### Requirement: Wasser-Karte im Ernährungstag

Ist „Wasser erfassen“ eingeschaltet, SHALL der Ernährungstag unter der Tageskarte eine Karte „Wasser“ zeigen: „Menge / Ziel ml“ in deutscher Zahlenformatierung, ein Fortschrittsbalken und die Schnellknöpfe „+200 ml“, „+300 ml“ und „+500 ml“. Ein Schnellknopf über der Obergrenze MUST deaktiviert sein. Antippen der Menge SHALL ein Sheet zum Korrigieren oder Zurücksetzen auf 0 ml öffnen. Fehler beim Speichern MUST in der Karte bzw. im offenen Sheet stehen. Bei Textgröße 2 DARF nichts überlaufen.

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

#### Scenario: Speichern scheitert

- **GIVEN** das Sheet „Wasser“ ist offen und der lokale Speicher lehnt die Änderung ab
- **WHEN** der Nutzer sichert
- **THEN** bleibt das Sheet offen, zeigt den Fehler und die Menge bleibt unverändert

#### Scenario: Grenze erreicht

- **GIVEN** heute sind 9.800 ml erfasst
- **WHEN** der Nutzer die Karte ansieht
- **THEN** sind „+300 ml“ und „+500 ml“ deaktiviert und „+200 ml“ ist verfügbar, weil es genau 10.000 ml ergibt
