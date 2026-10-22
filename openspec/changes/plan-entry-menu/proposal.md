# Proposal

## Why

Im aktiven Training lassen sich Übungen über das Übungsmenü verschieben, ersetzen und löschen. Im Planeditor ging das bisher nicht: Wer eine Übung im Plan umstellen oder austauschen wollte, musste sie entfernen und neu hinzufügen und dabei Sätze und Notiz neu eintragen.

## What Changes

- **Übungsmenü im Planeditor:** Jede Eintragskarte hat einen „…“-Knopf wie im Training. Langes Drücken öffnet dasselbe Menü. Oben stehen Verschieben, Ersetzen und Löschen, darunter „Sätze bearbeiten“. Ein Tipp auf die Karte öffnet weiter den Sätze-Editor.
- **Verschieben** nutzt das Neuordnen-Sheet des Trainings. Bei nur einem Eintrag wird es nicht angeboten.
- **Ersetzen** tauscht die Übung über die Übungsauswahl. Sätze, Notiz, Superset und Eintrags-ID bleiben.
- **Löschen** entfernt den Eintrag aus dem Entwurf.
- Ein Superset, das durch Verschieben oder Löschen nicht mehr zusammenhängt, wird aufgelöst.
- Alle Änderungen gelten erst mit „Speichern“.

### Non-Goals

- Keine Änderung an Planmodell, Backend oder Sync.

## Capabilities

- **Neu:** `plan-entry-menu`.

## Impact

- Flutter: Planeditor, Neuordnen-Sheet (verallgemeinert auf Training und Plan). Keine Backend- oder Sync-Änderung.
