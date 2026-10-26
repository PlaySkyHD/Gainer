# Proposal

## Why

Issue #221 (Review von PR #219, Bezug #175): Die Anforderung „Getrennte freiwillige Health-Berechtigungen“ verlangt, dass Gewicht-Lesezugriff und Workout-Schreibzugriff getrennt angefordert werden. Der Code fragt beim Check-in alle Check-in-Typen gemeinsam in einem Systemdialog an: Gewicht, Schritte und Schlaf lesen, Gewicht und Schlaf schreiben. Die Entscheidung ist gefallen: Der gemeinsame Dialog ist gewollt. Deshalb passt sich die Spec an den Code an, der Code bleibt unverändert.

## What Changes

Nur Specs ändern sich, kein Code.

- **body-tracking, MODIFIED:** Die Anforderung „Getrennte freiwillige Health-Berechtigungen“ fordert Health-Berechtigungen nur nach einer Nutzeraktion an. Gewichtsimport (Gewicht lesen) und Workout-Export (Workouts schreiben) sind jeweils eigene Anforderungen. Zwei Szenarien dazu sind neu.
- **body-tracking, ADDED:** Die Anforderung „Gemeinsamer Health-Dialog für Check-in-Typen“ hält fest, dass alle Check-in-Typen (lesen: Gewicht, Schritte, Schlaf; schreiben: Gewicht, Schlaf) in einer Systemanforderung stehen. Sie erfolgt beim Öffnen eines Check-ins oder beim Wechsel des Datums, nie beim Lesen der Übersicht. Dazu kommen Szenarien für die Übersicht und für fehlendes Health.

Die übrigen Szenarien der MODIFIED-Anforderung bleiben unverändert. Ihre Überschrift bleibt gleich, damit das Delta zuzuordnen ist. Der Text beider Anforderungen bleibt unter 500 Zeichen, Details stehen in den Szenarien.

Andere Specs widersprechen dem Code nicht: `overview` schließt einen Berechtigungsdialog beim Lesen der Schritte aus, und der Code fragt beim Lesen der Übersicht nicht an.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `body-tracking`: Die Anforderung zu den Health-Berechtigungen wird an den gemeinsamen Check-in-Dialog und die getrennten Anforderungen für Gewichtsimport und Workout-Export angepasst.

## Impact

- Nur `openspec/specs/body-tracking/spec.md` nach dem Archivieren, kein Code, keine API-Änderung.
- Der Workflow „OpenSpec“ bleibt grün, sobald der Change archiviert ist.
