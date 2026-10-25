# Proposal

## Why

Das Review von PR #132 (Issue #112) hat einen Blocker gefunden: Ältere App-Versionen brechen den Pull bei einem unbekannten Ressourcentyp ab und rücken den Cursor nicht vor. Der Change-Feed filtert nicht nach Client. Sobald ein neues Gerät Wasser schreibt, wäre der Sync jedes alten Geräts desselben Kontos dauerhaft blockiert, auch für Training und Ernährung, und es würde nur „Synchronisierung nicht möglich“ melden.

Weitere Befunde betreffen die Wasser-Ressource selbst:
- Eine Addition mit Basisversion bringt gegenüber einer Summe nichts.
- Zufällige IDs je Gerät können für denselben Tag einen Konflikt erzeugen, der sich nicht auflösen lässt.
- Ein Pull zwischen Lesen und Schreiben kann überschrieben werden.
- Fehler beim Speichern erscheinen nicht im Sheet.

## What Changes

- **Protokoll 4.** `SyncProtocol.CurrentVersion` steigt auf 4, Protokoll 2 und 3 bleiben erlaubt. Wasser setzt Protokoll 4 voraus.
- **Alte Apps schützen.**
  - Registrierung: Hat das Konto Wasser im Change-Feed und meldet sich eine App mit Protokoll unter 4 an, antwortet der Server mit `upgrade_required`. Diese Antwort zeigen auch bereits ausgelieferte Apps als „Aktualisiere die App, um die Synchronisierung fortzusetzen.“ an.
  - Pull: Er nennt seine Protokollversion. Ohne Angabe gilt 3, wie bei allen bisherigen Apps. Der Server liefert nur Batches bis vor die erste Änderung, die der Client nicht kennt. Gibt es davor nichts, antwortet er mit `upgrade_required`. Der Cursor rückt nie über eine solche Änderung hinaus.
- **Neue App.**
  - Sie sendet Protokoll 4 bei Registrierung, Push und Pull.
  - `upgrade_required` beim Pull und unbekannte Ressourcentypen enden als „Update nötig“. Der Cursor und die lokalen Daten bleiben unverändert. Ein Hinweis „Bitte App aktualisieren“ erscheint über allen Tabs.
  - Einträge, die eine alte Version wegen `upgrade_required` angehalten hat, sendet sie wieder.
- **Wasser nur als Summe.** `addWaterIntake` und `addedMl` entfallen. Jede Änderung ist `setWaterIntake` mit der neuen Tagesmenge. Die Basisversion verhindert stilles Überschreiben.
- **Feste ID je Nutzer und Tag.** Die App bildet die ID als UUID v5 aus Konto und Datum. Zwei Geräte schreiben denselben Tag damit unter derselben ID. Ein Konflikt lässt sich dann wie bei anderen Ressourcen lösen.
- **Lesen und Schreiben geprüft.** Der Commit prüft, dass der gelesene Stand noch gilt. Hat ein Pull oder eine Bestätigung den Tag geändert, liest die App neu und versucht es erneut.
- **Kleinere Korrekturen.**
  - Ein anderes Datum für eine bekannte ID ist `invalid_payload`, kein Versionskonflikt.
  - Fehler beim Speichern stehen im Sheet und in der Karte. Eine Wasseränderung löscht nur eigene Fehler.
  - Ein laufendes Neuladen überschreibt keine neuere Wassermenge.
  - Änderungen an den Ernährungs-Einstellungen laufen nacheinander.

### Non-Goals

- Ressourcen für alte Clients umwandeln oder weglassen; sie müssen aktualisieren.
- Eine Erzwingung von App-Updates außerhalb des Syncs.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `meal-tracking`: Wassermenge nur als Summe mit fester ID, geprüftes Schreiben, Fehleranzeige.
- `offline-sync`: neue Ressourcentypen nur für Clients mit passender Protokollversion.

## Impact

- Backend: `SyncProtocol`, `SyncResourceProtocol`, `SyncChangeFeed`, `SyncChangesController` (Query-Parameter `protocolVersion`), `SyncClientRegistry`, `SyncMutationProcessor`, Wasser-Handler.
- App: Protokoll 4, Pull mit Version, Update-Hinweis, Wasser-Repository, View-Model, Sheet.
- OpenAPI: neuer optionaler Query-Parameter.
