# Proposal

## Why

Die zweite Review-Runde zu PR #132 fand einen Blocker: Die Geräteübergabe registriert das neue iPhone mit Protokoll 3. Hat das Konto Wasser erfasst, lehnt der Server das mit `upgrade_required` ab. Damit scheitert der Gerätewechsel immer, und jede Übergabe setzt die gespeicherte Protokollversion zurück.

Dazu kamen weitere Befunde:
- **Endlosschleife:** angehaltene Einträge wurden bei jedem Push erneut gesendet.
- **Unklare Fehler:** Meldungen beim Speichern waren schwer verständlich.
- **Getarnter Unique-Fehler:** ein Unique-Fehler erschien als Versionskonflikt.
- **Kleinere Punkte** im Sync-Status und Pull-Bericht.
- **Sonar:** SHA-1 für die Tages-ID gilt als schwacher Hash.

## What Changes

- **Eine Protokollkonstante:** Alle Registrierungen der App, auch die Geräteübergabe, nutzen `nativeSyncProtocolVersion` (4).
- **Angehaltene Einträge nach Update:** Einträge mit `upgradeRequired` gehen nur wieder hinaus, wenn sich das Konto zuletzt mit einer älteren Protokollversion registriert hatte, also nach einem App-Update. Sonst bleiben sie liegen.
- **Hinweis und Bericht:**
  - Der Hinweis „Bitte App aktualisieren“ verschwindet erst nach einem Lauf, der den Server erreicht.
  - Der Bericht zählt Batches, die vor `upgrade_required` schon angewendet wurden.
- **Verständliche Meldungen beim Wasser:**
  - Eingefrorene Änderungen während einer Übergabe und ein Tag, der sich ständig ändert, ergeben deutsche Meldungen.
  - `local_sync_store.dart` wirft dafür typisierte Fehler.
- **Server:**
  - Eine zweite ID für einen belegten Tag ist `water_day_exists` (422) statt `stale_base_version`.
  - `SyncChangeFeed` verlangt immer die Protokollversion.
  - Die Sync-Controller teilen sich den ProblemDetails-Aufbau.
- **Tages-ID:** wird als UUID v8 (RFC 9562) aus SHA-256 gebildet statt als UUID v5 mit SHA-1. Wasser ist noch nicht ausgeliefert, alte IDs brauchen keine Migration.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `offline-sync`: gleiche Protokollversion bei allen Registrierungen, angehaltene Einträge nur nach Update.
- `meal-tracking`: Tages-ID mit SHA-256, eigener Code für eine zweite ID am selben Tag.

## Impact

- App: `sync_protocol.dart`, Sync- und Übergabe-Repository, Sync-Status, Wasser-Repository, lokaler Speicher.
- Backend: Wasser-Handler, Sync-Prozessor, Change-Feed, Sync-Controller.
