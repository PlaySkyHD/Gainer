## MODIFIED Requirements

### Requirement: Selbstheilung eindeutiger Konflikte

Lehnt der Server einen veralteten Zwischenstand ab und ist die Lage eindeutig, SHALL die App den Konflikt ohne Rückfrage lösen. Bei `stale_base_version` MUST der Server die aktuelle Version der Ressource nennen; ist sie neuer als jede gezogene Version, SHALL das Schreibgerät seinen Stand einmal je Ressource und Version darauf aufsetzen und erneut senden. Echte Doppeländerungen MUST weiterhin in der Konfliktliste erscheinen.

#### Scenario: Veraltetes aktives Training
- **GIVEN** der Server lehnt „Training anlegen“ mit „anderes Training aktiv“ ab und lokal ist das Training inzwischen beendet
- **WHEN** der Sync die Ablehnung erhält
- **THEN** sendet die App einmal automatisch das beendete Training und es entsteht kein Konflikt

#### Scenario: Verlorene Antwort auf eine Anlage
- **GIVEN** der Server hat „Training anlegen“ gespeichert, die Antwort erreichte die App nicht
- **WHEN** die App das Training erneut sendet und `stale_base_version` mit Serverversion 1 erhält
- **THEN** sendet sie ihren Stand als Speicherung auf Version 1 und es entsteht kein Konflikt

#### Scenario: Direkt übernommen
- **GIVEN** das Gerät hat gerade mit „Übernehmen“ das Schreibrecht erhalten und noch nicht gezogen
- **WHEN** ein Eintrag mit `stale_base_version` und einer unbekannten Serverversion abgelehnt wird
- **THEN** setzt die App nicht auf, sondern der Eintrag wird zum Konflikt, bis der Pull den Serverstand geliefert hat

### Requirement: Sichtbarer Sync-Zustand

Ist das Gerät nicht Schreibgerät, SHALL die App das in allen Tabs mit einer Übernahme-Möglichkeit anzeigen. Bestehen Konflikte, SHALL sie in allen Tabs die Anzahl nicht gespeicherter Änderungen mit einem Weg zur Konfliktliste zeigen. Unter Mehr SHALL der Zeitpunkt des letzten Syncs und die Anzahl wartender Änderungen stehen.

#### Scenario: Nicht Schreibgerät
- **GIVEN** ein anderes Gerät ist Schreibgerät
- **WHEN** der Nutzer einen beliebigen Tab öffnet
- **THEN** sieht er den Hinweis „Dieses iPhone lädt nichts hoch“ mit „Übernehmen“

#### Scenario: Abgelehnte Änderungen
- **GIVEN** zwei Trainings stehen im Konflikt
- **WHEN** der Nutzer einen beliebigen Tab öffnet
- **THEN** sieht er „2 Änderungen nicht gespeichert“ und „Ansehen“ öffnet die Konfliktliste
