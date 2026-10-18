# Proposal

## Why

Der Check-in fragt neben dem Gewicht Kalorien, Makros, Schritte und Schlaf ab. Kalorien und Makros kommen inzwischen aus dem Ernährungstagebuch, das bei den Auswertungen ohnehin Vorrang hat. Schritte und Schlaf zeichnet das iPhone meist schon in Apple Health auf. Das manuelle Abtippen ist umständlich und doppelt; Schlaf als Minutenwert zu schätzen ist schwer.

## What Changes

- Der Check-in besteht nur noch aus Datum, Gewicht (Pflicht), Schlaf und Schritten. Kalorien, Protein, Kohlenhydrate und Fett entfallen als Eingabe.
- **Gewicht:** wird mit dem jüngsten Apple-Health-Wert des Tages vorausgefüllt, bleibt editierbar. Liegt für den Tag kein Health-Wert vor, wird das gespeicherte Gewicht nach Health geschrieben.
- **Schlaf:** Eingabe als „Zu Bett“ und „Aufgestanden“ statt Minuten; die Dauer wird angezeigt und als Minuten gespeichert. Vorausfüllen aus der Health-Schlafanalyse der vorangehenden Nacht. Liegt dort nichts vor, wird der manuell eingetragene Schlaf als Schlafprobe nach Health geschrieben.
- **Schritte:** immer aus Apple Health (Tagessumme), nur Anzeige ohne Eingabe; ohne Daten ein Hinweis zum Verbinden.
- Neue HealthKit-Berechtigungen: Lesen Schritte und Schlaf, Schreiben Gewicht und Schlaf.

### Non-Goals

- Keine Backend-, Sync- oder Datenmodelländerung; die Felder für Kalorien und Makros bleiben für alte Check-ins erhalten.
- Kein Android/Health Connect (es gibt derzeit keine Android-App).
- Kein Hintergrundabgleich; Health wird nur beim Öffnen und Speichern des Check-ins gelesen bzw. geschrieben.

## Capabilities

- **Neu:** `health-check-in`.

## Impact

- Pigeon-API und `NativeHealthKit.swift` (neue Lese-/Schreibmethoden), `HealthPlatform`-Port, `body_screen.dart` (Check-in-Sheet), Tests.
