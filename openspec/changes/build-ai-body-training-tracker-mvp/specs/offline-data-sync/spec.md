## Purpose

Diese Capability stellt sicher, dass die Tracking-Kernreise ohne Netzverbindung zuverlässig bleibt und lokale Änderungen später nutzergebunden, idempotent und nachvollziehbar synchronisiert werden.

## ADDED Requirements

### Requirement: Offline verfügbare Kernreise

Die Anwendung MUST nach einem erfolgreichen Online-Start die lokal vorhandenen Check-ins, Ziele, Übungen, Templates, Rotation, laufenden Workouts, Previous Performance und Workout-Historie ohne Netzwerkverbindung lesbar machen und erlaubte Trackingänderungen offline annehmen. Online-Funktionen MUST offline eindeutig als nicht verfügbar gekennzeichnet werden.

#### Scenario: Training ohne Verbindung

- **GIVEN** App-Shell und benötigte Nutzerdaten wurden zuvor vollständig lokal gespeichert
- **WHEN** der Nutzer die PWA ohne Netzverbindung öffnet
- **THEN** kann er die lokale Kernreise verwenden und sieht den Offline-Zustand

#### Scenario: AI Coach offline öffnen

- **GIVEN** das Gerät besitzt keine Netzverbindung
- **WHEN** der Nutzer eine neue AI-Coach-Antwort anfordert
- **THEN** wird die Anfrage nicht vorgetäuscht, sondern als online erforderliche Funktion mit Retry-Möglichkeit angezeigt

### Requirement: Atomare lokale Änderung mit Outbox

Die Anwendung MUST jede synchronisierbare Fachänderung atomar gemeinsam mit einer stabilen, nutzergebundenen Mutation-ID in einer persistenten Outbox speichern, bevor sie in der UI als gespeichert bestätigt wird.

#### Scenario: Lokales Speichern gelingt

- **GIVEN** der Nutzer ändert gültige Trackingdaten
- **WHEN** Fachänderung und Outbox-Eintrag lokal geschrieben werden können
- **THEN** werden beide gemeinsam bestätigt und die UI zeigt den neuen lokalen Stand sofort an

#### Scenario: Lokales Speichern schlägt fehl

- **GIVEN** der lokale Speicher kann die atomare Transaktion nicht abschließen
- **WHEN** der Nutzer eine Änderung bestätigt
- **THEN** werden weder Fachänderung noch Outbox-Eintrag teilweise übernommen und die UI zeigt einen Fehler mit Retry-Möglichkeit

#### Scenario: PWA wird nach lokaler Bestätigung beendet

- **GIVEN** eine Änderung wurde lokal bestätigt, aber noch nicht serverseitig synchronisiert
- **WHEN** die PWA beendet und später neu geöffnet wird
- **THEN** bleiben Fachänderung und ausstehender Outbox-Eintrag für denselben Nutzer erhalten

### Requirement: Idempotenter Upload

Der Server MUST Client-Ressourcen-IDs und Mutation-IDs akzeptieren, jede Mutation pro Nutzer höchstens einmal wirksam anwenden und bei einem identischen Retry das bereits erzielte Ergebnis bestätigen.

#### Scenario: Bestätigung geht verloren

- **GIVEN** der Server hat eine Mutation gespeichert, aber die Bestätigung erreicht das Gerät nicht
- **WHEN** das Gerät dieselbe Mutation mit derselben ID erneut sendet
- **THEN** bestätigt der Server dasselbe Ergebnis und erzeugt weder Duplikat noch zusätzliche fachliche Wirkung

#### Scenario: Gleiche Mutation-ID mit abweichendem Inhalt

- **GIVEN** eine Mutation-ID wurde bereits mit einer bestimmten Nutzlast verarbeitet
- **WHEN** dieselbe ID mit abweichendem Inhalt erneut gesendet wird
- **THEN** lehnt der Server die Anfrage als Konflikt ab und behält den gespeicherten Stand unverändert

### Requirement: Nutzergebundener Revisionsabgleich und Löschmarkierungen

Der Server SHALL Änderungen über einen je Nutzer monoton fortschreitenden Revisionscursor bereitstellen. Löschungen MUST als Löschmarkierungen übertragen werden; der Client MUST abgerufene Änderungen und den neuen Cursor atomar lokal anwenden.

#### Scenario: Änderungen seit Cursor abrufen

- **GIVEN** der Client besitzt einen zuletzt bestätigten Revisionscursor
- **WHEN** er Änderungen seit diesem Cursor abruft
- **THEN** erhält er ausschließlich neuere Änderungen des authentifizierten Nutzers mit einem fortgeschriebenen Cursor

#### Scenario: Serverseitige Löschung übernehmen

- **GIVEN** eine eigene Ressource wurde seit dem letzten Sync serverseitig gelöscht
- **WHEN** der Client die zugehörige Löschmarkierung abruft
- **THEN** entfernt oder archiviert er die lokale Ressource gemäß ihrer Fachregel und setzt den Cursor in derselben lokalen Transaktion fort

#### Scenario: Lokale Anwendung eines Batches bricht ab

- **GIVEN** ein Änderungsbatch wurde heruntergeladen
- **WHEN** nicht alle Änderungen und der Cursor atomar lokal gespeichert werden können
- **THEN** bleibt der vorherige Cursor bestehen und der vollständige Batch kann erneut abgerufen werden

### Requirement: Unterbrechung und Retry ohne Datenverlust

Die Anwendung MUST ausstehende Mutationen bei Verbindungsfehler, Timeout, App-Abbruch oder Serverfehler erhalten und später mit derselben Mutation-ID erneut versuchen. Ein permanenter fachlicher Fehler SHALL den betroffenen Eintrag sichtbar blockieren, ohne andere unabhängige Einträge zu verlieren.

#### Scenario: Netzwerk bricht während Sync ab

- **GIVEN** mehrere lokale Mutationen warten auf Synchronisation
- **WHEN** die Verbindung während der Übertragung abbricht
- **THEN** bleiben alle nicht eindeutig bestätigten Mutationen ausstehend und können idempotent erneut gesendet werden

#### Scenario: Einzelne Mutation ist ungültig

- **GIVEN** ein ausstehender Eintrag verletzt eine aktuelle fachliche Validierung
- **WHEN** der Server ihn dauerhaft ablehnt
- **THEN** kennzeichnet die Anwendung genau diesen Eintrag mit verständlichem Fehler und lässt unabhängige gültige Einträge weiter synchronisieren

### Requirement: Abgelaufene Sitzung und Kontowechsel

Die Anwendung MUST bei `401 Unauthorized` den Sync anhalten, ausstehende Daten im lokalen Bereich des ursprünglichen Nutzers erhalten und eine erneute Anmeldung verlangen. Sie MUST verhindern, dass diese Daten unter einem später angemeldeten anderen Konto angezeigt oder gesendet werden.

#### Scenario: Sitzung läuft vor Upload ab

- **GIVEN** für Nutzer A stehen lokale Änderungen aus und seine Sitzung ist abgelaufen
- **WHEN** die Anwendung synchronisieren möchte
- **THEN** bleiben die Änderungen erhalten, der Sync pausiert und Nutzer A wird zur erneuten Anmeldung aufgefordert

#### Scenario: Anderer Nutzer meldet sich an

- **GIVEN** ausstehende Änderungen von Nutzer A liegen lokal vor
- **WHEN** sich Nutzer B auf demselben Gerät anmeldet
- **THEN** sieht und synchronisiert Nutzer B diese Änderungen nicht

### Requirement: Versionierte Konflikterkennung

Der Server MUST veränderliche Ressourcen gegen ihre vom Client angegebene Basisversion prüfen und darf konkurrierende Änderungen nicht still überschreiben. Die Anwendung SHALL den lokalen und den aktuellen Serverstand als behebbaren Konflikt anzeigen.

#### Scenario: Übereinstimmende Basisversion

- **GIVEN** die Basisversion der Mutation entspricht der aktuellen Serverversion
- **WHEN** der Server die gültige Mutation verarbeitet
- **THEN** speichert er die Änderung mit einer neuen Version

#### Scenario: Veraltete Basisversion

- **GIVEN** dieselbe Ressource wurde seit der lokalen Bearbeitung serverseitig verändert
- **WHEN** die Mutation mit veralteter Basisversion eintrifft
- **THEN** antwortet der Server mit `409 Conflict`, verändert die Ressource nicht und liefert die zur Auflösung nötige aktuelle Version

#### Scenario: Nutzer löst Konflikt auf

- **GIVEN** ein Konflikt enthält lokalen und aktuellen Serverstand
- **WHEN** der Nutzer ausdrücklich einen Stand übernimmt oder seine lokale Änderung auf die aktuelle Version erneut anwendet
- **THEN** wird eine neue Mutation mit der aktuellen Basisversion erzeugt und der verworfene Stand nicht stillschweigend verwendet

### Requirement: Begrenzter Mehrgeräte- und Hintergrundbetrieb

Das MVP MUST kenntlich machen, dass nur ein aktiv schreibendes Hauptgerät pro Nutzer unterstützt wird und parallele Offline-Änderungen mehrerer Geräte nicht automatisch zusammengeführt werden. Die Anwendung SHALL im Vordergrund, beim Start und nach wiederhergestellter Verbindung synchronisieren, darf aber keinen abgeschlossenen Sync während iOS-Suspendierung versprechen.

#### Scenario: Parallel auf zwei Geräten geändert

- **GIVEN** zwei Geräte ändern dieselbe Ressource ausgehend von derselben Basisversion
- **WHEN** beide Geräte synchronisieren
- **THEN** wird höchstens eine Änderung direkt akzeptiert und die andere als sichtbarer Konflikt behandelt

#### Scenario: PWA wird vor dem Hintergrund-Sync suspendiert

- **GIVEN** lokale Mutationen stehen aus und die PWA wird vom Betriebssystem suspendiert
- **WHEN** kein Hintergrundprozess ausgeführt wird
- **THEN** bleiben die Mutationen lokal ausstehend und der Sync wird beim nächsten geeigneten Vordergrundzeitpunkt erneut versucht

### Requirement: Verständlicher Synchronisationsstatus

Die Anwendung MUST pro Nutzer mindestens den Offline-Status, die Anzahl ausstehender Änderungen, laufenden Sync, Zeitpunkt des letzten Erfolgs sowie blockierte Authentifizierungs-, Validierungs- oder Konfliktfehler anzeigen.

#### Scenario: Alles synchronisiert

- **GIVEN** es bestehen keine ausstehenden oder blockierten Mutationen
- **WHEN** der Nutzer den Sync-Status öffnet
- **THEN** zeigt die Anwendung den letzten erfolgreichen Abgleich und den vollständig synchronisierten Zustand

#### Scenario: Manuelles Retry

- **GIVEN** ausstehende Mutationen konnten wegen eines vorübergehenden Fehlers nicht synchronisiert werden
- **WHEN** der Nutzer bei bestehender Verbindung einen erneuten Versuch auslöst
- **THEN** startet die Anwendung einen neuen idempotenten Sync und aktualisiert den sichtbaren Status
