# Proposal

## Why

Issue #279: Gingen zwei Refresh-Antworten nacheinander verloren, erlaubte der Server nur einen Retry mit dem Vorgänger-Token. Der zweite Retry galt als Wiederverwendung und meldete den Nutzer ab.

## What Changes

- Innerhalb der Kulanzfrist wird der unmittelbare Vorgänger wiederholt akzeptiert. Jeder Retry verwirft den zuletzt ausgestellten, nie benutzten Token und gibt einen neuen aus.
- Kehrt der zuletzt verworfene Token zurück, widerruft die API die Session. Nach Benutzung des Nachfolgers ist der Vorgänger kein Retry mehr, nach Ablauf der Frist ebenfalls nicht.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `account-access`: Anforderung „Wiederverwendung widerruft die Session“ erlaubt wiederholte Retries und ergänzt das Szenario „Zwei verlorene Antworten“.

## Impact

`DeviceSessionService` und Integrationstests in `AuthenticationApiTests`.
