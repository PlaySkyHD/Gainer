# sync-reliability

## ADDED Requirements

### Requirement: Ein wartender Stand je Ressource

Lokale Änderungen SHALL den noch nicht gesendeten Eintrag derselben Ressource ersetzen, sodass höchstens ein wartender Eintrag mit dem neuesten Stand übertragen wird. Bereits gesendete Einträge MUST unverändert bleiben.

#### Scenario: Offline begonnen und beendet
- **GIVEN** das Gerät ist offline
- **WHEN** der Nutzer ein Training startet, Sätze einträgt und es beendet
- **THEN** wartet genau ein Eintrag „Training anlegen“ mit dem beendeten Training

#### Scenario: Angelegt und gelöscht
- **GIVEN** ein lokal angelegtes, noch nicht gesendetes Training
- **WHEN** der Nutzer es löscht
- **THEN** wartet für dieses Training kein Eintrag mehr

### Requirement: Selbstheilung eindeutiger Konflikte

Lehnt der Server einen veralteten Zwischenstand ab und ist die Lage eindeutig, SHALL die App den Konflikt ohne Rückfrage lösen. Echte Doppeländerungen MUST weiterhin in der Konfliktliste erscheinen.

#### Scenario: Veraltetes aktives Training
- **GIVEN** der Server lehnt „Training anlegen“ mit „anderes Training aktiv“ ab und lokal ist das Training inzwischen beendet
- **WHEN** der Sync die Ablehnung erhält
- **THEN** sendet die App einmal automatisch das beendete Training und es entsteht kein Konflikt

### Requirement: Abhängigkeiten abwarten

Eine Änderung, die auf eine noch nicht vom Server bestätigte lokale Ressource verweist, SHALL erst nach dieser gesendet werden und MUST NOT wegen der fehlenden Referenz als Konflikt enden.

#### Scenario: Training mit neuer Übung
- **GIVEN** eine neue eigene Übung und ein Training damit, beide noch nicht gesendet
- **WHEN** synchronisiert wird
- **THEN** wird zuerst die Übung und danach das Training gesendet

### Requirement: Sichtbarer Sync-Zustand

Ist das Gerät nicht Schreibgerät, SHALL die App das in allen Tabs mit einer Übernahme-Möglichkeit anzeigen. Unter Mehr SHALL der Zeitpunkt des letzten Syncs und die Anzahl wartender Änderungen stehen.

#### Scenario: Nicht Schreibgerät
- **GIVEN** ein anderes Gerät ist Schreibgerät
- **WHEN** der Nutzer einen beliebigen Tab öffnet
- **THEN** sieht er den Hinweis „Dieses iPhone lädt nichts hoch“ mit „Übernehmen“
