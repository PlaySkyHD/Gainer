# Proposal

## Why

Issue #221 (Review von PR #219, Bezug #175): Die Anforderung „Getrennte freiwillige Health-Berechtigungen“ verlangt, dass Gewicht-Lesezugriff und Workout-Schreibzugriff getrennt angefordert werden. Das Check-in-Formular fragt dagegen alle Check-in-Typen gemeinsam in einem Systemdialog an: Gewicht, Schritte und Schlaf lesen, Gewicht und Schlaf schreiben. Die Entscheidung ist gefallen: Der gemeinsame Dialog im Check-in-Formular ist gewollt. Deshalb passt sich die Spec an den Code an, der Code bleibt unverändert.

## What Changes

Nur Specs ändern sich, kein Code.

- **body-tracking, RENAMED und MODIFIED:** Die Anforderung „Getrennte freiwillige Health-Berechtigungen“ heißt jetzt „Freiwillige Health-Berechtigungen nach Nutzeraktion“. Sie verlangt Health-Berechtigungen nur nach einer Nutzeraktion. Gewichtsimport und Workout-Export sind jeweils eigene Anforderungen. Entzug und Ablehnung lassen die Kernreise nutzbar. Zwei Szenarien dazu sind neu.
- **body-tracking, ADDED:** Die Anforderung „Gemeinsamer Health-Dialog im Check-in-Formular“ gilt nur für das Check-in-Formular. Dort löst das Öffnen oder der Datumswechsel genau eine Systemanforderung für alle Check-in-Typen aus. Das Lesen der Übersicht löst keine aus.

Die übrigen Szenarien der MODIFIED-Anforderung bleiben unverändert.

Andere Specs widersprechen dem Code nicht: `overview` schließt einen Berechtigungsdialog beim Lesen der Schritte aus, und der Code fragt beim Lesen der Übersicht nicht an.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `body-tracking`: Die Anforderung zu den Health-Berechtigungen wird umbenannt und angepasst. Der gemeinsame Check-in-Dialog kommt als eigene Anforderung dazu.

## Impact

- Nur `openspec/specs/body-tracking/spec.md` nach dem Archivieren, kein Code, keine API-Änderung.
