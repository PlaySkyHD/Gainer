# Proposal

## Why

Issue #274: Bei assistierten Übungen ist das Gewicht die Unterstützung. Der Aufwärmhinweis rechnete trotzdem Bruchteile des Vorwerts und schlug damit weniger Unterstützung, also schwerere Sätze als den Arbeitssatz vor.

## What Changes

- Für assistierte Übungen erscheint kein Aufwärmhinweis. „Als Aufwärmsätze eintragen“ wird dort nicht angeboten.
- Andere Übungstypen bleiben unverändert.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `training-session`: Anforderung „Aufwärmhinweis anzeigen“ nimmt assistierte Übungen aus.

## Impact

`WorkoutViewModel.warmupHintFor` und Test in `workout_view_model_test.dart`.
