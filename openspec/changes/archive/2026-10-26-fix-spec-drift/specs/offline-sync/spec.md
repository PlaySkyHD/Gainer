## MODIFIED Requirements

### Requirement: Sync-Protokoll-Parität

Die App MUST die aktuelle Protokollversion verwenden, stabile Mutation-IDs, Reihenfolge/Dependencies, aktive Writer-Regeln, idempotenten Replay, Tombstones und atomare Batch-/Cursor-Übernahme respektieren. Timeout, Prozessabbruch, 401, 409, Serverfehler und inkompatibles Protokoll MUST nachvollziehbar behandelt werden. Garantierter iOS-Hintergrund-Sync DARF nicht vorausgesetzt werden.

#### Scenario: Antwort nach Serverannahme geht verloren
- **GIVEN** der Server hat eine Mutation angewendet
- **WHEN** die Antwort verloren geht und der Client nach Neustart erneut sendet
- **THEN** verwendet er dieselbe Mutation-ID und erzeugt keine zusätzliche fachliche Wirkung

#### Scenario: Konflikt bewusst lösen
- **GIVEN** lokale und serverseitige Änderungen kollidieren
- **WHEN** der Nutzer den sichtbaren Konflikt löst
- **THEN** bleibt der alte Stand nachvollziehbar und eine bestätigte neue Änderung verwendet eine neue Mutation-ID und die aktuelle Basisversion

#### Scenario: Pull-Commit scheitert
- **GIVEN** ein heruntergeladener Batch enthält Änderungen und einen neuen Cursor
- **WHEN** dessen lokale Transaktion abbricht
- **THEN** bleibt der alte Cursor erhalten und derselbe Batch kann vollständig erneut angewendet werden
