# Proposal

## Why

Der Statistikbereich zeigt Trainingstage, Cardio, Muskeln und Rekorde je Übung. Wie sich das Training insgesamt entwickelt (wie oft, wie lange, wie viel Volumen, Sätze und Wiederholungen, dazu das Körpergewicht), sieht der Nutzer nirgends auf einen Blick. Die Werte je Training berechnet die App schon für die Zusammenfassung nach dem Training.

## What Changes

- Neuer Bereich „Verlauf“ unter der Heatmap mit Zeitraum-Umschalter (4 W, 3 M, 1 J, Alle; Standard 3 M).
- Acht Kacheln mit Wert für den Zeitraum und Linie je Woche (4 W, 3 M) oder Monat (1 J, Alle): Trainings pro Woche, Ø Trainingsdauer, Gesamtzeit, Volumen, Sätze, Wiederholungen, Ø Wiederholungen pro Satz, Körpergewicht.
- Dieselbe Datengrundlage und dieselben Formeln wie Rekorde und Übungsstatistik, inklusive Aufwärmsatz-Schalter.
- Ohne Training und Check-in entfällt der Bereich. Bei großer Schrift stehen die Kacheln untereinander.

## Capabilities

### New Capabilities

Keine.

### Modified Capabilities

- `training-statistics`: neue Anforderungen „Verlauf im Statistikbereich“, „Abschnitte des Verlaufs“, „Kennzahlen des Verlaufs“ und „Körpergewicht im Verlauf“.

## Impact

Neu: `lib/domain/models/training/training_trends.dart`, `lib/ui/features/training/training_trend_tiles.dart`. Geändert: `TrainingStatisticsViewModel`, `TrainingStatisticsSection`, Goldens der Statistikliste. Kein Backend, kein Sync.
