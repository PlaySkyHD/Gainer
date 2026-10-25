## MODIFIED Requirements

### Requirement: Wassermenge pro Tag

Das System SHALL pro Nutzer und lokalem Kalendertag höchstens eine Wassermenge in ganzen Millilitern speichern, unter einer festen ID je Nutzer und Tag (UUID v8 aus SHA-256). Die Menge MUST zwischen 0 und 10.000 ml liegen. Jede Änderung MUST die neue Tagesmenge setzen, die Basisversion prüfen und die Version erhöhen. Ein anderes Datum für eine bekannte ID und eine zweite ID für einen belegten Tag MUST als ungültig abgelehnt werden. Ein Tag mit 0 ml SHALL bestehen bleiben.

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

#### Scenario: Zweite ID für einen belegten Tag

- **GIVEN** für den 25.10.2026 ist Wasser unter einer ID gespeichert
- **WHEN** eine Mutation mit einer anderen ID denselben Tag anlegen will
- **THEN** antwortet der Server mit `water_day_exists` statt mit einem Versionskonflikt und ändert nichts

#### Scenario: Falsches Datum für eine bekannte ID

- **GIVEN** die ID eines Tages gehört zum 25.10.2026
- **WHEN** eine Mutation dieselbe ID mit dem 26.10.2026 sendet
- **THEN** antwortet der Server mit `invalid_payload` und ändert nichts
