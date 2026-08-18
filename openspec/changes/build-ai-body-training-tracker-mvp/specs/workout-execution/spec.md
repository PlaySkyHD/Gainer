## Purpose

Diese Capability definiert das offline-taugliche Durchführen von Workouts einschließlich Previous Performance, Satzprotokoll, Pausentimer und unveränderlicher Historie.

## ADDED Requirements

### Requirement: Workout aus einem Ausgangs-Snapshot starten

Das System MUST ein Workout online wie offline aus einem lokal verfügbaren eigenen Template starten können. Dabei SHALL es eine stabile Workout-ID sowie einen Snapshot von Template-Name, Übungs-IDs und -Namen, Reihenfolge, Zielvorgaben, Pausenzeiten und Notizen anlegen.

#### Scenario: Eigenes Template offline starten

- **GIVEN** das eigene Template und seine Übungen sind lokal vollständig verfügbar und das Gerät ist offline
- **WHEN** der Nutzer das Workout startet
- **THEN** wird sofort ein lokales Workout mit stabiler ID und vollständigem Ausgangs-Snapshot angelegt

#### Scenario: Template ist offline nicht vollständig verfügbar

- **GIVEN** der vollständige Stand des ausgewählten Templates ist lokal nicht vorhanden
- **WHEN** der Nutzer offline versucht, das Workout zu starten
- **THEN** wird der Start verständlich abgelehnt und kein unvollständiges Workout angelegt

#### Scenario: Fremdes Template starten

- **GIVEN** Nutzer A kennt die Template-ID von Nutzer B
- **WHEN** Nutzer A versucht, daraus ein Workout zu starten
- **THEN** lehnt das Backend den Start ohne Offenlegung von Template-Inhalten ab und erzeugt kein Workout

### Requirement: Bearbeitbares Satzprotokoll

Das System SHALL in einem laufenden Workout das Hinzufügen, Entfernen und Umordnen von Übungen und Sätzen sowie das Bearbeiten von Gewicht, Wiederholungen, optionalem RIR und Notizen erlauben. Ein abgeschlossener Satz MUST ein nicht negatives endliches Gewicht, eine positive ganzzahlige Wiederholungszahl und optional RIR zwischen 0 und 10 besitzen.

#### Scenario: Satz offline abschließen

- **GIVEN** ein Workout läuft ohne Netzwerkverbindung
- **WHEN** der Nutzer 102,5 kg und 8 Wiederholungen einträgt und den Satz abschließt
- **THEN** erscheint der Satz sofort lokal als abgeschlossen und ist für die spätere Synchronisation vorgemerkt

#### Scenario: Ungültige Satzdaten

- **GIVEN** ein Satz besitzt ein negatives Gewicht oder keine positive ganzzahlige Wiederholungszahl
- **WHEN** der Nutzer ihn als abgeschlossen markiert
- **THEN** wird der Abschluss mit feldbezogenen Fehlern abgelehnt und der zuletzt gültige Stand bleibt erhalten

#### Scenario: Workout-Anpassung verändert kein Template

- **GIVEN** ein Nutzer verändert Übungen oder Sätze in einem laufenden Workout
- **WHEN** er die Änderung speichert
- **THEN** wird ausschließlich der Workout-Snapshot verändert und nicht das zugrunde liegende Template

### Requirement: Previous Performance aus eigener Historie

Das System MUST für jede Workout-Übung die Satzleistung aus dem zeitlich letzten, vor Start des aktuellen Workouts abgeschlossenen Workout desselben Nutzers und derselben stabilen Übungs-ID anzeigen. Unvollständige Workouts und Daten anderer Nutzer dürfen nicht einfließen.

#### Scenario: Vorherige Leistung vorhanden

- **GIVEN** der Nutzer hat zuletzt dieselbe Übung mit 100 kg für 8 Wiederholungen abgeschlossen
- **WHEN** er ein neues Workout mit derselben stabilen Übungs-ID öffnet
- **THEN** zeigt die Anwendung 100 kg × 8 als entsprechende vorherige Satzleistung an

#### Scenario: Keine passende lokale Historie

- **GIVEN** das Gerät ist offline und lokal existiert kein passendes abgeschlossenes Workout dieses Nutzers
- **WHEN** Previous Performance angezeigt werden soll
- **THEN** kennzeichnet die Anwendung den fehlenden lokalen Wert und zeigt weder geschätzte noch fremde Werte an

### Requirement: Offline-fähiger Pausentimer

Das System MUST nach Abschluss eines gültigen Satzes automatisch die im Workout-Snapshot hinterlegte positive Pausenzeit starten. Der Timer SHALL einen Zielzeitpunkt verwenden, Navigation, Offline-Betrieb und App-Unterbrechungen überstehen sowie `+30 Sekunden`, `Neustart` und `Überspringen` anbieten.

#### Scenario: Timer nach Satzabschluss

- **GIVEN** die Übung besitzt eine Pausenzeit von 180 Sekunden
- **WHEN** der Nutzer einen gültigen Satz erstmals abschließt
- **THEN** startet genau ein Timer mit 180 Sekunden Restzeit

#### Scenario: App während der Pause unterbrochen

- **GIVEN** ein Timer besitzt einen gespeicherten Zielzeitpunkt und die PWA wird suspendiert
- **WHEN** der Nutzer die PWA später wieder öffnet
- **THEN** wird die verbleibende Zeit aus dem Zielzeitpunkt neu berechnet und nicht um die Unterbrechungsdauer verlängert

#### Scenario: Keine Pausenzeit gesetzt

- **GIVEN** für die Übung ist keine positive Pausenzeit gesetzt
- **WHEN** ein Satz abgeschlossen wird
- **THEN** startet kein automatischer Pausentimer

### Requirement: Workout abschließen und historisieren

Das System MUST ein Workout mit mindestens einem abgeschlossenen Satz als vollständigen Snapshot mit Start- und Abschlusszeitpunkt historisieren. Nach Abschluss SHALL der Snapshot durch reguläre UI-, API-, Template- oder Sync-Operationen unveränderlich bleiben.

#### Scenario: Workout erfolgreich abschließen

- **GIVEN** ein eigenes laufendes Workout enthält mindestens einen gültig abgeschlossenen Satz
- **WHEN** der Nutzer das Workout abschließt
- **THEN** erscheint es mit vollständigem Snapshot und Dauer in seiner Historie und steht für Previous Performance bereit

#### Scenario: Leeres Workout abschließen

- **GIVEN** ein laufendes Workout enthält keinen abgeschlossenen Satz
- **WHEN** der Nutzer es abschließen möchte
- **THEN** wird der Abschluss abgelehnt und das Workout bleibt laufend

#### Scenario: Historischen Satz verändern

- **GIVEN** ein Workout ist bereits abgeschlossen
- **WHEN** eine reguläre Operation einen historischen Satz ändern oder löschen möchte
- **THEN** wird die gesamte Operation als Konflikt abgelehnt und der Snapshot bleibt unverändert

#### Scenario: Template nachträglich ändern

- **GIVEN** ein aus diesem Template gestartetes Workout ist abgeschlossen
- **WHEN** das Template oder eine Katalogübung später geändert oder archiviert wird
- **THEN** bleiben Namen, Reihenfolge, Vorgaben und Satzwerte im historischen Workout unverändert

### Requirement: Laufendes Workout wiederherstellen oder abbrechen

Das System SHALL ein lokal gespeichertes laufendes Workout nach Navigation, App-Neustart oder Betriebssystemunterbrechung für denselben Nutzer wiederherstellen. Ein ausdrücklicher Abbruch MUST bestätigt werden und darf nicht in Historie, Previous Performance oder Rotationsfortschritt einfließen.

#### Scenario: PWA unbeabsichtigt schließen

- **GIVEN** ein Workout läuft und ist lokal gespeichert
- **WHEN** die PWA ohne bestätigten Abbruch geschlossen und erneut geöffnet wird
- **THEN** kann derselbe Nutzer das Workout mit seinem zuletzt gespeicherten Stand fortsetzen

#### Scenario: Workout ausdrücklich abbrechen

- **GIVEN** ein laufendes Workout enthält gespeicherte Sätze
- **WHEN** der Nutzer den Abbruch ausdrücklich bestätigt
- **THEN** wird es verworfen und verändert weder Previous Performance noch den nächsten Rotationsschritt

### Requirement: Nutzerisolierte Workout-Historie

Das System MUST Liste, Detailansicht, Previous Performance und Synchronisation von Workouts an die authentifizierte Nutzer-ID binden und fremde Workout-IDs ohne Datenoffenlegung ablehnen.

#### Scenario: Fremdes historisches Workout abrufen

- **GIVEN** Nutzer A kennt die Workout-ID eines abgeschlossenen Workouts von Nutzer B
- **WHEN** Nutzer A dessen Details oder Satzdaten anfordert
- **THEN** antwortet die API mit `404 Not Found` und gibt keine Workout-Inhalte zurück

#### Scenario: Manipulierte Nutzer-ID synchronisieren

- **GIVEN** eine Sync-Nutzlast enthält eine fremde oder manipulierte Nutzer-ID
- **WHEN** das Backend die Workout-Änderung verarbeitet
- **THEN** lehnt es die Nutzlast ab und ordnet keine Daten einem anderen als dem authentifizierten Nutzer zu
