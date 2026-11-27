# Proposal

## Why

Bei einem Nutzer mit nur einem Gerät landeten fünf Trainings im Konflikt, ohne dass er es merkte. Das Training „Pull 2“ wurde mit `stale_base_version` abgelehnt („Auf dem Server gibt es eine neuere Version“) und blieb auf dem Server aktiv. Alle folgenden Trainings scheiterten deshalb an „anderes Training aktiv“. Auch „Lokalen Stand erzwingen“ half nicht.

Typische Ursache: eine verlorene Antwort im Funkloch. Der Server speichert die Änderung, die App erhält die Antwort nicht und sendet ihren Stand erneut, mit der alten Basisversion oder als zweite Anlage. Der Server nennt in der Ablehnung bisher keine Version. Die vorhandene Selbstheilung greift nur, wenn lokal ein neuerer Stand vorliegt und der Pull den Serverstand geliefert hat.

## What Changes

- Der Server nennt bei `stale_base_version` die aktuelle Version der einzigen Ressource der Mutation (`serverVersion`, `serverDeleted`) aus dem Änderungsfeed des Nutzers.
- Die App setzt ihren Stand einmal je Ressource und Serverversion automatisch auf diese Version auf und sendet ihn erneut, wenn die Version neuer ist als alles, was sie gezogen hat. Bekannte, also gezogene Versionen bleiben bei der bisherigen Prüfung auf fremde Änderungen.
- Konflikte werden sichtbar: Ein Hinweis über allen Tabs nennt die Anzahl nicht gespeicherter Änderungen und öffnet mit „Ansehen“ die Konfliktliste.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `offline-sync`: Anforderungen „Selbstheilung eindeutiger Konflikte“ und „Sichtbarer Sync-Zustand“.

## Impact

Backend: `SyncMutationConflictException`, `SyncMutationProcessor`, `SyncMutationsController` (neue optionale Problem-Felder, keine Protokolländerung). App: `ApiProblem`, `ApiException`, `SyncRepository`, `LocalConflictRecovery.requeueLocalState`, `SyncStatus`, `SyncStatusBanner`, `MobileShell`.
