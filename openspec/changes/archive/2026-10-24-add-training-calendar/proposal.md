# Proposal

## Why

Die bisherige Rotation kennt nur eine Reihenfolge von Plänen. Ruhetage, feste Wochentage und ein Datumsbezug fehlen, deshalb kann die App nicht sagen, was heute oder an einem bestimmten Tag ansteht. Gleichzeitig gibt es keinen Ort, an dem man für einen Tag sieht, was passiert ist: Training, Cardio, Ernährung und Check-in liegen in getrennten Tabs.

## What Changes

- **Trainingsrhythmus** ersetzt die Rotation. Es gibt zwei Modi:
  - **Zyklus:** eine geordnete Folge aus Plänen und Ruhetagen, z. B. `Push · Pull · Beine · Ruhe`. Die Länge ist frei (1–28 Tage), die Wochentage wandern mit.
  - **Feste Tage:** jedem Wochentag (Mo–So) ist ein Plan oder ein Ruhetag zugeordnet.
- Der Rhythmus ist **ans Datum gebunden** und ändert sich nur durch ausdrückliche Aktionen. Ein anderes Training als geplant zu machen, ändert den Rhythmus nicht.
- **Tagesaktionen** für ein geplantes Training:
  - **Rhythmus verschieben** (nur Zyklus) um 1 oder 2 Tage: dieses und alle folgenden Trainings rücken nach.
  - **Nur dieses verschieben** auf morgen oder übermorgen: alles andere bleibt auf seinem Datum.
  - **Überspringen:** dieses Training fällt weg, alles andere bleibt.
  - Ein **verpasstes** Training (höchstens 7 Tage alt) lässt sich **heute nachholen**. Im Zyklus gibt es zusätzlich **„Ab heute weiter“**, das den ganzen Rhythmus verschiebt.
  - Eine Verschiebung auf heute oder einen späteren Tag lässt sich **aufheben**.
- **Neuer Tab „Kalender“ ersetzt den Tab „Heute“.** Oben steht ein Monatsraster mit Markierungen für erledigtes Krafttraining, Cardio, Check-in, geplante und verpasste Trainings. Darunter folgt die Tagesansicht des gewählten Tages mit Plan, Trainings, Ernährung und Check-in. Für heute bleiben die bisherigen Inhalte des Heute-Tabs erhalten.
- Im Trainings-Tab ersetzt die Karte **„Heute: Push · Starten“** bzw. „Ruhetag“ den bisherigen Rotationsvorschlag. Der Button „Rotation“ wird zu „Rhythmus“.

### Non-Goals

- Mehrere gespeicherte Rhythmen und Wechsel zwischen ihnen (spätere Phase).
- Erinnerungen per Mitteilung, Deload-Wochen, Cardio-Slots im Rhythmus, Widgets.
- Berechnung der Vorschau im Backend; sie läuft vollständig auf dem Gerät.
- Bearbeiten von Ernährung oder Check-in direkt im Kalender. Der Kalender verlinkt in die bestehenden Tabs.
- Freies Verschieben von Trainings per Ziehen im Kalender.

## Capabilities

- **Neu:** `training-schedule`: Rhythmus, Vorschau, Tagesaktionen, Erfüllung.
- **Neu:** `calendar-tab`: Kalender-Tab mit Monatsraster und Tagesansicht.
- **Entfällt:** die Anforderung „Plan-Rotation“ aus `training-plans` (Change `rebuild-training-logging`).

## Kernjourney

Gehört zur privaten Kernjourney (Training planen und durchführen). Die Non-Goals sind spätere Phasen.

## Breaking Changes

- `WorkoutRotation` wird ersatzlos entfernt: Tabellen, Mutation `SaveWorkoutRotation`, `ResourceKind.WorkoutRotation`, `WorkoutRotationQueries`, der lokale Typ `workout-rotation` und `plan_rotation_sheet.dart`. Laut Nutzer verwendet niemand die Rotation, deshalb gibt es **keine Datenübernahme**.
- Der Tab „Heute“ (`MobileArea.progress`) heißt „Kalender“ und hat eine neue Struktur. Die erwarteten Screenshots in `scripts/Verify-Mobile.ps1` ändern sich.
- Ältere App-Stände senden möglicherweise noch Rotations-Mutationen. Der Server lehnt sie als unbekannte Operation ab. Die neue App verwirft lokale `workout-rotation`-Daten und offene Outbox-Einträge dazu beim Datenbank-Upgrade.

## Security

- Der Rhythmus ist eine nutzerbezogene Ressource mit `UserId`. Die API leitet den Nutzer aus der Sitzung ab.
- Beim Speichern MUSS jede Plan-ID im Rhythmus dem angemeldeten Nutzer gehören. Fremde oder unbekannte IDs sind ein Validierungsfehler und kein Hinweis auf fremde Daten. Das wird mit zwei Testnutzern geprüft.
- Es gibt keine neuen Endpunkte außerhalb des Sync-Vertrags und keine AI-Beteiligung.

## Impact

- **Backend:**
  - `Gainer.Core/Training`: neu `TrainingSchedule*`, `WorkoutRotation*` entfällt.
  - `ResourceKey` (neuer `ResourceKind.TrainingSchedule`), `SyncMutationExecutor`, `SyncMutationProcessor`, `SyncMutationsController`.
  - `AppDbContext`, EF-Migration (Rotation löschen, Rhythmus anlegen), `GainerPersistenceExtensions`.
  - Contracts unter `src/Gainer.Contracts/Sync` bzw. `Training`.
- **Flutter:**
  - Daten: `training_log_repository.dart`, `sync_payload_codec.dart`, `local_database.dart` (Upgrade-Schritt), `workout_rules.dart`.
  - Neues Domänenmodell `training_schedule.dart` mit reiner Vorschau-Funktion.
  - Training-UI: `training_plans_section.dart` und `training_plans_view_model.dart`, Rhythmus-Editor neu.
  - Shell und Kalender: `mobile_shell_view_model.dart`, `mobile_shell.dart`, `progress_screen.dart` (geht im Kalender auf), neuer Ordner `ui/features/calendar/`.
- **Tests:** Unit-Tests für die Vorschau (Dart), Integrationstests für Speichern, Version und Isolation (C#), Goldens für Kalender und Rhythmus-Editor, `Verify-Mobile.ps1`.
