## ADDED Requirements

### Requirement: Neue Ressourcen nur für Apps, die sie kennen

Jeder Ressourcentyp SHALL ein Mindestprotokoll haben. Ein Pull ohne `protocolVersion` MUST als Protokoll 3 gelten. Der Server DARF einem Client keine Änderung eines Typs liefern, den dessen Protokoll nicht kennt, und MUST davor anhalten. Ist davor nichts zu liefern oder registriert sich ein solcher Client bei einem Konto mit solchen Änderungen, MUST er mit `upgrade_required` antworten.

#### Scenario: Alte App nach dem ersten Wasser

- **GIVEN** ein Gerät des Kontos hat Wasser erfasst und ein zweites Gerät hat eine App mit Protokoll 3
- **WHEN** das zweite Gerät synchronisiert
- **THEN** antwortet die Registrierung mit `upgrade_required`, die App zeigt „Aktualisiere die App, um die Synchronisierung fortzusetzen.“ und behält ihre offenen Änderungen

#### Scenario: Pull ohne Protokollangabe

- **GIVEN** der Feed enthält eine Check-in-Änderung und danach eine Wasser-Änderung
- **WHEN** ein Client ohne `protocolVersion` abruft
- **THEN** erhält er die Check-in-Änderung mit Protokoll 3 in der Antwort, und der nächste Abruf ab diesem Cursor endet mit `upgrade_required`

#### Scenario: Neue App

- **GIVEN** derselbe Feed
- **WHEN** eine App mit Protokoll 4 abruft
- **THEN** erhält sie beide Änderungen und die Antwort meldet Protokoll 4

### Requirement: Update nötig ohne Datenverlust

Die App MUST bei Registrierung, Push und Pull ihre Protokollversion nennen. Unbekannte Ressourcentypen und `upgrade_required` MUST sie als „Bitte App aktualisieren“ melden, ohne den Cursor zu bewegen oder lokale Daten zu verlieren. Einträge, die eine ältere Version wegen `upgrade_required` angehalten hat, SHALL sie nach erfolgreicher Registrierung wieder senden.

#### Scenario: Unbekannter Typ in der neuen App

- **GIVEN** der Server liefert einen Ressourcentyp, den die App nicht kennt
- **WHEN** die App den Batch anwenden will
- **THEN** rollt sie ihn zurück, behält den Cursor und zeigt „Bitte App aktualisieren“

#### Scenario: Nach dem Update

- **GIVEN** eine ältere App hat offene Einträge wegen `upgrade_required` angehalten
- **WHEN** die aktualisierte App sich erfolgreich registriert
- **THEN** sendet sie diese Einträge wieder
