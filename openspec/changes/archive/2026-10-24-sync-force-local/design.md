# Design

## Decisions

### D1 – Erzwingen je Ressource

`forceLocalState(conflictId, replacementMutationId, createdAtUtc)` im `LocalConflictRecovery` in einer Transaktion:
1. Konflikt, Ressource (Envelope mit `workingCopy`, `serverVersion`) und alle Outbox-Zeilen der Ressource lesen (aufsteigend nach `sequence`).
2. Lokal gelöscht = letzte Outbox-Operation ist `delete` oder die Arbeitskopie trägt eine Löschmarke.
3. Fall „lokal gelöscht, Server kennt sie nicht“ (`serverVersion == null`): Outbox-Zeilen, Ressource und Konflikt entfernen; nichts senden.
4. Sonst eine neue Outbox-Zeile mit der kleinsten bisherigen `sequence`, Operation `create` (ohne Serverversion), `delete` (lokal gelöscht) oder `update` (mit `baseVersion = serverVersion`), Nutzlast = aktuelle Arbeitskopie im selben Format, das das jeweilige Repository beim normalen Speichern erzeugt; alte Zeilen und Konflikt entfernen, Envelope auf `pending`.
5. Server-Löschmarken (Tombstones) werden nie wiederbelebt: Existiert ein Tombstone, wirft die Methode wie bisher.

Nur für Aggregattypen, deren Mutationsnutzlast der Arbeitskopie entspricht (Training, Plan, eigene Übung, Kategorie und alle weiteren, bei denen das zutrifft – im Code prüfen). Für andere Typen bleibt die Aktion ausgeblendet.

### D2 – Mehrfachauswahl und Reihenfolge

Die Sync-Ansicht erhält einen Auswahlmodus. „Lokalen Stand erzwingen“ verarbeitet die ausgewählten Konflikte nach der ursprünglichen `sequence` ihrer ersten Outbox-Zeile, damit referenzierte Übungen und Pläne vor Trainings ankommen, und startet anschließend einen Sync. „Serverstand übernehmen“ verarbeitet nur Konflikte mit Serverstand.

### D3 – Darstellung

Konfliktzeile: Titel der Ressource aus der Arbeitskopie (z. B. Trainingstitel und Datum), Typ, Grund als deutscher Text je Code (`active_workout_exists`, `validation_failed`, `stale_base_version`, `resource_not_found`, sonst allgemeiner Text). Aktionen per Kontext-Sheet bzw. in der Auswahl-Toolbar; Bestätigungsdialog vor dem Erzwingen mit Hinweis, dass der Serverstand dieser Einträge überschrieben wird.
