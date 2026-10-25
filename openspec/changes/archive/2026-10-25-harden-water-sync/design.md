# Design

## Decisions

### D1 – Woher der Server die Protokollversion eines Pulls kennt

Der Pull-Aufruf trug bisher weder Client-ID noch Protokoll. Ausgelieferte Apps prüfen außerdem, dass die Antwort Protokoll 3 meldet, und werfen sonst eine `FormatException`. Daraus folgt:

- Der Pull bekommt den optionalen Query-Parameter `protocolVersion`. Fehlt er, gilt 3 (`SyncProtocol.UnversionedPullVersion`), und die Antwort meldet 3. Mit Angabe meldet sie die angefragte Version.
- Eine Version über `CurrentVersion` ist ein Validierungsfehler (400). Eine unter `PreviousVersion` ergibt `upgrade_required`.

Die Zuordnung „Ressourcentyp → Mindestprotokoll“ liegt in Core (`SyncResourceProtocol`), damit Feed, Registrierung und Mutationen dieselbe Regel nutzen. Infrastructure darf Contracts nur über Konstanten nutzen (Architekturtest).

### D2 – Alte Apps sehen eine verständliche Meldung

Bereits ausgelieferte Apps behandeln `upgrade_required` nur bei der Registrierung. Sie zeigen dann „Aktualisiere die App …“ und parken offene Einträge mit Status `upgradeRequired`. Beim Pull zeigen sie bei jedem Fehler nur „Synchronisierung nicht möglich“.

Deshalb prüft die Registrierung: Hat das Konto Änderungen eines Typs, den das gemeldete Protokoll nicht kennt, antwortet sie mit `upgrade_required`. Die App registriert sich vor jedem Sync, die Meldung kommt also vor dem Pull. Ein Konto ohne Wasser bleibt für alte Apps unverändert nutzbar.

Der Pull-Schutz (D3) bleibt zusätzlich bestehen, falls zwischen Registrierung und Pull Wasser hinzukommt.

### D3 – Feed hält vor unbekannten Batches an

`SyncChangeFeed.GetAsync(after, limit, clientProtocolVersion)` liefert die Batches bis vor den ersten Batch mit einem Typ, den der Client nicht kennt. Dann gilt `hasMore = true`, `UpgradeRequired = true`, und der Cursor zeigt auf den letzten gelieferten Batch. Ist die Seite leer, antwortet der Controller mit 409 `upgrade_required`. Ein alter Client bekommt so alle älteren Änderungen, rückt aber nie über eine Wasser-Änderung hinaus. Nach dem Update holt er sie nach.

### D4 – Neue App: Update nötig statt Abbruch

Die App meldet Protokoll 4 bei Registrierung, Push und Pull. In diesen Fällen endet der Lauf mit `SyncRunState.upgradeRequired`:

- `upgrade_required` beim Pull,
- ein unbekannter Ressourcentyp im Batch (`UnsupportedSyncResourceException`).

Die Batch-Transaktion rollt dabei zurück: kein Cursor, keine Teiländerung. Der `SyncStatusTracker` merkt sich den Zustand, und das Banner zeigt über allen Tabs „Bitte App aktualisieren“. Der nächste Lauf, der den Server erreicht, blendet es wieder aus.

Nach erfolgreicher Registrierung setzt die App Einträge mit Status `upgradeRequired` wieder auf `pending`. Diesen Status hatte eine ältere Version gesetzt, und ohne diese Rücksetzung blieben die Einträge nach dem Update für immer liegen.

### D5 – Wasser nur als Summe

Mit Basisversion ist eine Addition gleichwertig zu „Summe setzen“. Eine Differenz würde dagegen beim Zusammenfassen in der Outbox verloren gehen. Es gibt nur noch `setWaterIntake` (`SetWaterIntakeMutation`), und der Body entspricht der Arbeitskopie. „Lokalen Stand erzwingen“ und Selbstheilung brauchen damit keinen Sonderfall.

### D6 – Feste ID je Nutzer und Tag

Ernährungstage und Check-ins nutzen zufällige IDs. Legen zwei Geräte denselben Tag an, entsteht dort ein Unique-Konflikt unter zwei IDs. Ihn kann „Lokalen Stand erzwingen“ nicht lösen, weil der Serverstand unter der anderen ID nie zur lokalen Ressource gehört.

Für Wasser bildet die App die ID deshalb als UUID v5 aus einem festen Namensraum und `<kontoId>:<datum>` (SHA-1 aus dem Paket `crypto`, bisher schon transitiv vorhanden). So schreiben alle Geräte denselben Tag unter derselben ID. Ein Doppelschreiben wird ein normaler `stale_base_version`-Konflikt, den Pull und Selbstheilung auflösen. Die Suche nach dem Tag ist ein direkter Schlüsselzugriff, statt alle Wassertage zu dekodieren.

Der Server prüft die ID nicht, er behält den Unique-Index je Nutzer und Datum. Gehört eine bekannte ID zu einem anderen Datum, ist die Anfrage fehlerhaft (`invalid_payload`) statt veraltet.

### D7 – Lesen und Schreiben geprüft

`WaterIntakeRepository` liest den Tag, berechnet die neue Summe und übergibt `commitMutation` eine `LocalResourceExpectation` mit der gelesenen optimistischen und Serverversion. Hat ein Pull oder eine Bestätigung den Tag dazwischen geändert, schlägt der Commit atomar fehl. Das Repository liest dann neu und versucht es bis zu dreimal. Eigene Änderungen laufen weiter nacheinander durch eine Warteschlange.

### D8 – App-Zustand und Fehler

- **Eigener Fehlerbereich:** `NutritionErrorOperation.water`. Wasserfehler stehen in der Karte und im Sheet, das bei einem Fehler offen bleibt. Eine Wasseränderung löscht nur Wasserfehler.
- **Neuladen:** Das View-Model zählt gespeicherte Wasseränderungen. Kam während eines Ladens eine Änderung für denselben Tag an, übernimmt es deren Summe statt des gelesenen älteren Werts.
- **Einstellungen:** `NutritionPreferences.update` läuft durch eine Warteschlange, sodass Schalter und Ziel sich nicht gegenseitig überschreiben.

## Risks / Trade-offs

- **Alte Geräte desselben Kontos:** Sie müssen aktualisieren, sobald auf irgendeinem Gerät des Kontos Wasser erfasst wurde. Das ist gewollt, weil sie die Daten nicht anwenden können.
- **Zusätzliche Abfrage:** Die Registrierungsprüfung fragt bei alten Clients die Change-Items des Nutzers ab. Für Clients mit Protokoll 4 entfällt die Abfrage.
