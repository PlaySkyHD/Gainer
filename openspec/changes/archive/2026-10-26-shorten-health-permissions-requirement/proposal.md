# Proposal

## Why

Der vorige Change `align-health-checkin-permissions` ergänzte die Anforderung „Getrennte freiwillige Health-Berechtigungen“ um Details. Der Text ist dadurch über 500 Zeichen lang, und `openspec validate --specs --strict` schlägt fehl. Die Details stehen bereits in Szenarien und in der neuen Anforderung „Gemeinsamer Health-Dialog für Check-in-Typen“.

## What Changes

- **body-tracking:** Der Text der Anforderung „Getrennte freiwillige Health-Berechtigungen“ wird auf die Grundregeln gekürzt. Die Szenarien bleiben unverändert.

Kein Code, keine API-Änderung.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `body-tracking`: Textkürzung einer Anforderung.

## Impact

- Nur `openspec/specs/body-tracking/spec.md` nach dem Archivieren.
