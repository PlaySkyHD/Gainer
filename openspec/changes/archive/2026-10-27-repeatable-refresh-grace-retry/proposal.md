# Proposal

## Why

Issue #279: Gingen zwei Refresh-Antworten nacheinander verloren, erlaubte der Server nur einen Retry mit dem Vorgänger-Token. Der zweite Retry galt als Wiederverwendung und meldete den Nutzer ab.

## What Changes

- Innerhalb der Kulanzfrist wird der unmittelbare Vorgänger wiederholt akzeptiert. Jeder Retry verwirft den zuletzt ausgestellten, nie benutzten Token und gibt einen neuen aus.
- Jeder verworfene Token wird gespeichert (Tabelle `device_session_discarded_tokens`, ersetzt die Spalte `DiscardedRefreshTokenHash`). Kehrt einer zurück, widerruft die API die Session. Wie die bisherige Spalte bleiben die Einträge erhalten, bis der erste Retry einer späteren Rotation sie ablöst; normale Rotationen löschen nichts.
- Höchstens zehn Retries je Rotation, der elfte widerruft die Session. Das begrenzt das Wachstum der Tabelle.
- Nach Benutzung des Nachfolgers ist der Vorgänger kein Retry mehr, nach Ablauf der Frist ebenfalls nicht.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `account-access`: Anforderung „Wiederverwendung widerruft die Session“ erlaubt wiederholte Retries und ergänzt das Szenario „Zwei verlorene Antworten“.

## Impact

`DeviceSessionService`, neue Entität `DeviceSessionDiscardedToken` mit Migration (übernimmt vorhandene verworfene Hashes) und Integrationstests in `AuthenticationApiTests`.
