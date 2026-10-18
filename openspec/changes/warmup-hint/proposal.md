# Proposal

## Why

Vor dem ersten Arbeitssatz wärmen viele Nutzer mit festen Anteilen ihres Arbeitsgewichts auf, etwa 50 % und 80 %. Diese Sätze möchten sie meist nicht tracken, müssen die Gewichte aber jedes Mal im Kopf ausrechnen.

## What Changes

- **Aufwärmhinweis:** In der Übungskarte eines aktiven Trainings steht über dem ersten Arbeitssatz eine Zeile „Aufwärmen 40 kg · 65 kg“. Basis ist das Gewicht des ersten Arbeitssatzes aus dem Vorwert der Übung. Ohne Vorwert mit Gewicht erscheint nichts. Der Hinweis wird nicht gespeichert und fließt nicht in Statistiken ein.
- **Globale Einstellungen:** Schalter „Aufwärmhinweis“ (Standard an), Standardstufen (anfangs 50 % und 80 %, je optional mit Wiederholungen), Schalter „Wiederholungen anzeigen“ (Standard aus).
- **Pro Übung:** eigene Stufen, eigene Rundung (Standard 2,5 kg bzw. 5 lb) oder Hinweis für diese Übung aus.
- **Eintragen:** Ein Tipp auf die Zeile bietet „Als Aufwärmsätze eintragen“ an; die Stufen werden dann als erfasste Aufwärmsätze vor dem ersten Arbeitssatz angelegt.

### Non-Goals

- Keine Synchronisierung der Aufwärmeinstellungen; sie sind wie die übrigen Trainingseinstellungen lokal pro Konto auf dem Gerät.
- Keine Scheibenrechnung je Hantelseite.

## Capabilities

- **Neu:** `warmup-hint`.

## Impact

- Flutter: Trainingseinstellungen, Übungseditor, Übungskarte im Training, Workout-ViewModel. Keine Backend- oder Sync-Änderung.
