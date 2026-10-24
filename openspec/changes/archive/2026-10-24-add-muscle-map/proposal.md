# Proposal

## Why

Bisher ist nicht zu erkennen, welche Muskeln ein Plan oder das tatsächliche Training abdeckt. Übungen haben nur ein freies Textfeld „Zielmuskel“, das die App weder anzeigt noch auswerten kann. Nutzer wollen auf einen Blick sehen, welche Muskeln sie trainieren und welche zu kurz kommen.

## What Changes

- **Feste Muskelliste:** 17 Regionen (Brust, vordere/seitliche/hintere Schulter, Bizeps, Trizeps, Unterarme, Bauch, seitliche Bauchmuskeln, Latissimus, oberer Rücken, unterer Rücken, Gesäß, Quadrizeps, Beinbeuger, Adduktoren, Waden).
- **Haupt- und Hilfsmuskeln je Übung:** Eigene Übungen bekommen im Übungseditor einen Abschnitt „Muskeln“. Basisübungen bringen die Werte aus dem Katalog mit. Das Freitextfeld bleibt unverändert und wird nicht angezeigt.
- **Körperkarte:** Vorder- und Rückansicht. Die Farbe einer Region zeigt die Zahl der Arbeitssätze. Hauptmuskeln zählen einen ganzen Satz, Hilfsmuskeln einen halben.
- **Muskelübersicht** (Statistik-Segment → „Muskeln“) mit zwei Quellen:
  - **Geplant:** alle aktiven Pläne zusammen oder ein einzelner Plan.
  - **Trainiert:** abgeschlossene Trainings der letzten 7 Tage oder Ø pro Woche der letzten 28 Tage.
  - Liste aller Muskeln mit Satzzahl. Ein Tipp zeigt die beitragenden Übungen.
  - Ein Hinweis nennt Übungen ohne Muskelangabe.
- **Plan-Editor:** Karte „Muskeln“ mit der Körperkarte des Plans, berechnet aus dem aktuellen, auch ungespeicherten Stand.
- **Sync und API:** `primaryMuscles` und `secondaryMuscles` an eigenen Übungen und im Katalog.

### Non-Goals

- Keine Bearbeitung der Muskeln von Basisübungen.
- Keine Erholungskarte, keine Übungsvorschläge für Lücken und keine Warnungen zu Ungleichgewichten. Das sind mögliche Folgeschritte.
- Keine Häufigkeit pro Woche für Pläne. „Geplant“ zählt jeden aktiven Plan einmal.

## Capabilities

- **Neu:** `muscle-map`.

## Impact

- Backend: `Exercise`, Katalog-JSON, EF-Migration, Validierung eigener Übungen, Katalog-Antwort, OpenAPI.
- Flutter: Übungsmodell, Sync-Codec, API-Modelle, Übungseditor, Plan-Editor, Statistik-Segment, neuer Screen und neues Widget für die Körperkarte.
