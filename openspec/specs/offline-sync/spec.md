# offline-sync Specification

## Purpose
Die App speichert Fachdaten offline-first pro Konto und synchronisiert sie über einen idempotenten, versionierten Sync-Vertrag mit dem Server. Ein Gerät ist Schreibgerät; der Wechsel läuft über eine abgesicherte Geräteübergabe oder eine bewusste Übernahme.

## Requirements

### Requirement: Offline verfügbare Kernreise

Die Anwendung MUST nach einem erfolgreichen Online-Start die lokal vorhandenen Check-ins, Ziele, Übungen, Pläne, Rhythmus, laufenden Trainings, Vorwerte, Trainingshistorie, Cardio-Einheiten und Ernährungsdaten ohne Netzwerkverbindung lesbar machen und erlaubte Trackingänderungen offline annehmen. Online-Funktionen MUST offline eindeutig als nicht verfügbar gekennzeichnet werden.

#### Scenario: Training ohne Verbindung

- **GIVEN** die benötigten Nutzerdaten wurden zuvor lokal gespeichert
- **WHEN** der Nutzer die App ohne Netzverbindung öffnet
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

#### Scenario: App wird nach lokaler Bestätigung beendet

- **GIVEN** eine Änderung wurde lokal bestätigt, aber noch nicht serverseitig synchronisiert
- **WHEN** die App beendet und später neu geöffnet wird
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

Die App MUST kenntlich machen, dass nur ein aktiv schreibendes Gerät pro Nutzer unterstützt wird und parallele Offline-Änderungen mehrerer Geräte nicht automatisch zusammengeführt werden. Die Anwendung SHALL im Vordergrund, beim Start und nach wiederhergestellter Verbindung synchronisieren, darf aber keinen abgeschlossenen Sync während iOS-Suspendierung versprechen.

#### Scenario: Parallel auf zwei Geräten geändert

- **GIVEN** zwei Geräte ändern dieselbe Ressource ausgehend von derselben Basisversion
- **WHEN** beide Geräte synchronisieren
- **THEN** wird höchstens eine Änderung direkt akzeptiert und die andere als sichtbarer Konflikt behandelt

#### Scenario: App wird vor dem Sync suspendiert

- **GIVEN** lokale Mutationen stehen aus und die App wird von iOS suspendiert
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

Die App MUST Protokoll v3, stabile Mutation-IDs, Reihenfolge/Dependencies, aktive Writer-Regeln, idempotenten Replay, Tombstones und atomare Batch-/Cursor-Übernahme respektieren. Timeout, Prozessabbruch, 401, 409, Serverfehler und inkompatibles Protokoll MUST nachvollziehbar behandelt werden. Garantierter iOS-Hintergrund-Sync DARF nicht vorausgesetzt werden.

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

### Requirement: Abgesicherte Geräteübergabe

Das Schreibgerät SHALL seine Schreibrechte an eine andere eigene Installation übergeben können, nachdem es alle offenen Änderungen gesendet hat. Der Server MUST die Übergabe an Konto, Quelle und bestätigte Revision binden, einen Einmalcode ausgeben, sie nach 15 Minuten verfallen lassen und währenddessen Mutationen ablehnen. Das Ziel MUST registriert sein und bis zur gesperrten Revision gelesen haben. Ein ungültiger Code DARF keinen Wechsel auslösen. Lokale Daten bleiben erhalten.

#### Scenario: Übergabe gelingt
- **GIVEN** das alte iPhone ist Schreibgerät und hat keine offenen Änderungen
- **WHEN** der Nutzer dort „Dieses Gerät ablösen“ wählt und auf dem neuen iPhone die Übergabedaten einfügt und den Gerätewechsel bestätigt
- **THEN** ist nur noch das neue iPhone Schreibgerät, und beide behalten ihre lokalen Daten

#### Scenario: Server hat sich geändert
- **GIVEN** zwischen Bestätigung der Revision und Beginn der Übergabe kam eine Änderung an
- **WHEN** die Quelle die Übergabe beginnt
- **THEN** lehnt der Server mit `stale_revision` ab und die Quelle bleibt Schreibgerät

#### Scenario: Abbruch, Ablauf oder verlorene Antwort
- **GIVEN** eine Übergabe ist begonnen
- **WHEN** die Quelle sie abbricht, sie abläuft oder die Antwort auf den Abschluss verloren geht
- **THEN** bleibt ohne Abschluss die Quelle Schreibgerät, ein wiederholter erfolgreicher Abschluss desselben Ziels ist idempotent und kein fremdes Gerät erhält Schreibrechte

#### Scenario: Abschluss nach Absturz
- **GIVEN** der Server hat den Abschluss angewendet und die App wurde vor der Antwort beendet
- **WHEN** die App aus ihrem geschützten Übergabe-Datensatz im Keychain neu startet
- **THEN** gleicht sie denselben Abschluss ab, erlaubt erst danach Schreibzugriffe und erzeugt keine zweite Übernahme

### Requirement: Direkte Übernahme nach einer Übergabe gesperrt

Nach der ersten abgeschlossenen Übergabe MUST der Server eine direkte Übernahme der Schreibrechte für dieses Konto mit `handover_required` ablehnen. Solange eine Übergabe läuft, MUST er eine direkte Übernahme mit `handover_in_progress` ablehnen. Eine Registrierung ohne Übernahme bleibt möglich.

#### Scenario: Übernahme nach Gerätewechsel
- **GIVEN** das Konto hat die Schreibrechte einmal per Übergabe gewechselt
- **WHEN** ein anderes Gerät die Schreibrechte direkt übernehmen will
- **THEN** antwortet der Server mit `handover_required` und das Schreibgerät bleibt unverändert

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

### Requirement: Lokalen Stand erzwingen

Für einen Sync-Konflikt SHALL der Nutzer den aktuellen lokalen Stand der Ressource erzwingen können. Die App MUST alle wartenden Änderungen dieser Ressource durch eine Änderung ersetzen, die den lokalen Stand überträgt, und MUST Server-Löschungen nicht wiederbeleben.

#### Scenario: Altes aktives Training
- **GIVEN** ein Konflikt „active_workout_exists“ für ein Training, das lokal inzwischen beendet ist und auf dem Server nicht existiert
- **WHEN** der Nutzer „Lokalen Stand erzwingen“ wählt und bestätigt
- **THEN** sendet die App das beendete Training als Neuanlage und der Konflikt verschwindet nach erfolgreichem Sync

#### Scenario: Lokal gelöscht und nie auf dem Server
- **GIVEN** ein Konflikt für ein Training, das lokal gelöscht ist und auf dem Server nie existierte
- **WHEN** der Nutzer den lokalen Stand erzwingt
- **THEN** werden Konflikt und wartende Änderungen entfernt und nichts gesendet

### Requirement: Konflikte gesammelt lösen

Die Konfliktliste SHALL eine Mehrfachauswahl mit „Alle auswählen“ bieten. Gesammeltes Erzwingen MUST in der ursprünglichen Reihenfolge der Änderungen erfolgen und anschließend synchronisieren.

#### Scenario: Übung vor Training
- **GIVEN** Konflikte für eine eigene Übung und ein Training, das diese Übung nutzt
- **WHEN** der Nutzer beide auswählt und erzwingt
- **THEN** wird die Übung vor dem Training gesendet

### Requirement: Verständliche Konfliktgründe

Jede Konfliktzeile SHALL den Namen der Ressource und einen deutschen Grund zeigen. „Serverstand nutzen“ MUST nur angeboten werden, wenn ein Serverstand vorhanden ist.

#### Scenario: Ohne Serverstand
- **GIVEN** ein Konflikt für ein Training, das der Server nie hatte
- **WHEN** die Konfliktliste angezeigt wird
- **THEN** fehlt „Serverstand nutzen“ und „Lokalen Stand erzwingen“ ist verfügbar

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
