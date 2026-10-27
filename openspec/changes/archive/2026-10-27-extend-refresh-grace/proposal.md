# Proposal

## Why

Issue #263: Geht die Antwort eines Refresh verloren, bleibt der alte Token beim Client. Nach einer Minute galt seine Wiederholung als Wiederverwendung und meldete den Nutzer ab, etwa wenn die App im Hintergrund war.

## What Changes

- Der unmittelbare Vorgänger-Token wird bis zu `Security:DeviceSessions:ReuseGracePeriod` nach der Rotation noch einmal akzeptiert, Standard 6 Stunden statt 1 Minute.
- Ältere Tokens sind unbekannt und bleiben abgelehnt. Der verworfene Token einer Wiederholung widerruft weiter die Session.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `account-access`: Anforderung „Wiederverwendung widerruft die Session“ nennt die konfigurierbare Frist.

## Impact

`DeviceSessionService` (Standardwert) und Integrationstests in `AuthenticationApiTests`.
