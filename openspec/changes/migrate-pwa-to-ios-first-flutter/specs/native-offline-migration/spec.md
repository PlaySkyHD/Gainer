## Purpose

Diese Capability erhält kontoisolierte Offline-Daten und das bestehende Sync-Verhalten und ermöglicht einen überprüfbaren, abbrechbaren Wechsel von der PWA zur nativen App.

## ADDED Requirements

### Requirement: Dauerhafte atomare Offline-Daten

Die App MUST Fachänderung und Outbox atomar vor der Speicherbestätigung sichern und Konto-Daten, Cursor, Konflikte, Tombstones und historische Snapshots dauerhaft isolieren. Schema-Upgrades MUST bestehende Daten erhalten oder vollständig zurückrollen. Fehlgeschlagene Transaktionen DÜRFEN weder teilweise Änderungen noch eine Speicherbestätigung erzeugen.

#### Scenario: Prozessende nach Bestätigung
- **GIVEN** eine offline gespeicherte Mutation von Konto A
- **WHEN** der Prozess beendet und die App ohne Netz wieder geöffnet wird
- **THEN** bleiben Fachdaten und dieselbe Mutation-ID erhalten und sind ausschließlich im lokalen Profil A verfügbar

#### Scenario: Speicherupgrade bricht ab
- **GIVEN** ein vorhandenes lokales Schema mit ausstehenden Mutationen
- **WHEN** ein Schema-Upgrade oder Fach-/Outbox-Commit scheitert
- **THEN** bleibt der letzte konsistente Stand erhalten und die App zeigt einen Wiederherstellungspfad ohne stilles Zurücksetzen

### Requirement: Sync-Protokoll-Parität

Die App MUST Protokoll v2, stabile Mutation-IDs, Reihenfolge/Dependencies, aktive Writer-Regeln, idempotenten Replay, Tombstones und atomare Batch-/Cursor-Übernahme respektieren. Timeout, Prozessabbruch, 401, 409, Serverfehler und inkompatibles Protokoll MUST nachvollziehbar behandelt werden. Garantierter iOS-Hintergrund-Sync DARF nicht vorausgesetzt werden.

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

### Requirement: Abgesicherte PWA-Übergabe

Die PWA MUST vor einer Übergabe Schreibaktionen einfrieren, alle offenen Mutationen synchronisieren, Konflikte auflösen und den aktuellen Serverstand bestätigen. Der Server MUST die Übergabe an Konto, bisherigen Writer und Serverrevision binden und während der befristeten Übergabe neue Mutationen und konkurrierende Writer-Übernahmen blockieren. Der native Client MUST vor einmaligem Abschluss vollständig bis zur gesperrten Revision gelesen haben. Eine abgelaufene, fremde oder bereits verbrauchte Übergabeberechtigung DARF keine Writer-Übernahme auslösen. Lokale PWA-Daten DÜRFEN nicht automatisch gelöscht werden.

#### Scenario: PWA hat ausstehende Änderungen
- **GIVEN** die PWA besitzt ausstehende, blockierte oder konfliktbehaftete Änderungen
- **WHEN** der Nutzer die Migration beginnt
- **THEN** bleibt die Übernahme gesperrt, die PWA behält sämtliche Daten und bietet Sync-/Konfliktbehebung an

#### Scenario: Race mit einem späten Schreibrequest
- **GIVEN** die PWA meldet einen bestätigten Revisionsstand für eine Übergabe
- **WHEN** eine gleichzeitig eintreffende Mutation oder Writer-Übernahme konkurriert
- **THEN** wird eine konsistente Reihenfolge hergestellt und die Übergabe wird bei veraltetem Stand abgelehnt oder die konkurrierende Änderung durch die aktive Sperre verweigert

#### Scenario: Übergabe gelingt
- **GIVEN** die PWA-Outbox ist leer, Konflikte sind gelöst und der Server sperrt die bestätigte Revision
- **WHEN** derselbe Nutzer den Stand vollständig nativ lädt und die Übergabe bestätigt
- **THEN** wird ausschließlich die native Installation Writer, die PWA zeigt ihren inaktiven Zustand und beide behalten ihre lokalen Daten

#### Scenario: Übergabe abbrechen oder wiederholen
- **GIVEN** eine Übergabe ist vorbereitet, läuft ab oder der Abschlussrequest verliert seine Antwort
- **WHEN** Abbruch, Ablauf oder Retry erfolgt
- **THEN** bleibt die bisherige Installation bei nicht erfolgtem Abschluss Writer, ein gleicher erfolgreicher Abschluss ist idempotent und keine fremde Installation erhält Zugriff

#### Scenario: Verwaister Push und altes PWA-Schema
- **GIVEN** eine ältere PWA-Datenbank oder eine nach Prozessende verbliebene syncing-Mutation
- **WHEN** die PWA nach Upgrade und exklusiver Wiederanlaufprüfung ihre Übergabe vorbereitet
- **THEN** wird dieselbe Mutation sicher wiederholt, ohne einen aktiven Push parallel zu senden, und Begin bleibt bis zu bestätigtem Drain und gelösten Konflikten gesperrt

#### Scenario: Abschluss nach Crash rekonstruieren
- **GIVEN** der Server hat Complete angewendet und der Client wurde vor Empfang der Antwort beendet
- **WHEN** die App aus ihrem geschützten Übergabe-Checkpoint startet
- **THEN** verwendet sie dasselbe Ziel und denselben Abschluss zur Reconciliation, erlaubt erst danach Fachwrites und erzeugt keine zweite Übernahme

### Requirement: Kontrollierter Rückwechsel

Ein Rückwechsel zur PWA MUST denselben Übergabeprozess mit dem nativen Client als Quelle verwenden. Eine PWA mit veralteten eigenen ausstehenden Änderungen MUST vor Aktivierung eine explizite Recovery-/Konfliktprüfung durchführen. Nach der ersten erfolgreichen abgesicherten Übergabe MUST der Server direkte Writerwechsel über den bisherigen Takeover-Pfad dauerhaft für dieses Konto ablehnen, auch bei alter PWA-Version; Registrierung ohne Writerwechsel MUST nutzbar bleiben. Unmigrierte Konten MUST ihr bisheriges Verhalten behalten.

#### Scenario: Native Offline-Daten vor Rückwechsel
- **GIVEN** der native Client besitzt noch nicht synchronisierte Daten
- **WHEN** der Nutzer zur PWA zurückkehren möchte
- **THEN** bleibt der Rückwechsel blockiert bis Sync und Konfliktprüfung abgeschlossen sind, ohne Daten zu löschen

#### Scenario: Alter Tab versucht direkte Rückübernahme
- **GIVEN** ein migriertes Konto mit nativem Writer und ein noch authentifizierter alter PWA-Tab
- **WHEN** der Tab die bisherige direkte Writer-Übernahme anfordert
- **THEN** lehnt der Server den Writerwechsel mit erklärtem Übergabebedarf ab und die aktualisierte PWA führt nur über den geprüften Rückwechsel
