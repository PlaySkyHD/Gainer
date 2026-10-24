# Proposal

## Why

Der Basiskatalog hat nur 14 englisch benannte Übungen. Fast alles legen Nutzer selbst an und müssen danach die Muskeln für die Muskelkarte nachtragen.

## What Changes

- **Kuratierter Basiskatalog:** 103 gängige Übungen auf Deutsch mit Equipment, Haupt- und Hilfsmuskeln, Kategorien und einer kurzen Technik-Anleitung. Die 14 bisherigen Übungen behalten ihre IDs und bekommen deutsche Namen.
- **Neue Kategorie „Unterarme“.**
- **Anleitung und Equipment** erscheinen in der Ansicht einer Basisübung.
- **Muskel-Vorschlag beim Anlegen:** Solange eine Übung keine Muskeln hat, schlägt der Editor die Muskeln der ähnlichsten Übung mit Muskeln vor (Katalog oder eigene). Ein Tipp übernimmt sie.

### Non-Goals

- Keine Bilder oder Animationen. Die Medien des geprüften Datasets sind nicht frei lizenziert.
- Eigene Übungen werden nicht automatisch mit Katalogübungen zusammengeführt; dafür gibt es „Mit anderer Übung zusammenführen“.

## Capabilities

- **Neu:** `exercise-catalog-de`.

## Impact

- Backend: Katalog-JSON (Version 2026.10.3), Beschreibung im Seed, EF-Migration.
- Flutter: Übungseditor (Vorschlag, Anleitung, Equipment), reine Vorschlagslogik.
