# Design

## Context

Motivation und Umfang: siehe `proposal.md`. Verhalten: siehe `specs/training-schedule` und `specs/calendar-tab`.

Ist-Zustand:

- **Backend:** `WorkoutRotation` und `WorkoutRotationItem` speichern eine Plan-Reihenfolge und werden über `SaveWorkoutRotationMutation` gespeichert (Sync-Vertrag mit `ResourceKind.WorkoutRotation`). `WorkoutRotationQueries.NextPlanIdAsync` ist registriert, wird aber von keinem Endpunkt genutzt.
- **Flutter:** Die Rotation liegt als Aggregat `workout-rotation` in `LocalResources`. `workout_rules.nextRotationPlanId` leitet den Vorschlag aus dem letzten beendeten Training ab. Ernährung (`NutritionRepository.read(localDate)`), Check-ins (`BodyRepository`, `localDate`), Trainings und Cardio sind lokal nach Tag lesbar.
- **Shell:** fünf Tabs (`MobileArea`: Heute, Check-in, Essen, Training, Mehr). Mehr passen nicht.

## Goals / Non-Goals

**Goals:**

- Ein Aggregat „Rhythmus“, das als vollständiger Stand über den bestehenden Sync-Vertrag läuft.
- Die Vorschau ist eine reine, deterministische Dart-Funktion und vollständig unit-testbar.
- Der Kalender braucht keine neue Server-API.

**Non-Goals:** siehe `proposal.md`.

## Decisions

### D1 – Datenmodell

`TrainingSchedule` (höchstens eine je Nutzer):

| Feld | Bedeutung |
| --- | --- |
| `Id`, `UserId`, `Version`, `CreatedAtUtc`, `UpdatedAtUtc` | wie bei anderen Aggregaten |
| `Mode` | `cycle` oder `weekly` |
| `AnchorDate` (`DateOnly`) | nur Zyklus: Datum, an dem Slot 0 liegt, ohne Verschiebungen |
| `ValidFrom` (`DateOnly`) | Tag der letzten Änderung an Modus oder Slots |

`TrainingScheduleSlot`: `Position`, `PlanId?` (`null` = Ruhetag). Bei `weekly` gilt Position 0 = Montag.

`TrainingScheduleShift`: `FromDate`, `Days` (1–31). Nur im Zyklus.

`TrainingScheduleException`: `Date`, `PlanId`, `MovedToDate?` (`null` = übersprungen).

Kinder werden bei jeder Mutation vollständig ersetzt, wie bei Plan-Einträgen. Bei einer Änderung an Modus oder Slots verwirft der Client alle Verschiebungen und Ausnahmen, weil sie sich auf den alten Rhythmus beziehen.

*Alternative:* nur einen Anker speichern und ihn bei „Rhythmus verschieben“ neu setzen. Verworfen, weil sich dann rückwirkend die geplanten Tage der Vergangenheit ändern und „verpasst“ falsch würde.

### D2 – Vorschau-Algorithmus (Dart, `domain/models/training/training_schedule.dart`)

```
planFor(date):
  if date < validFrom: none
  if weekly: slot = slots[date.weekday - 1]
  if cycle:
    applied = shifts.where(s.fromDate <= date)
    if any s in applied with date < s.fromDate + s.days: paused
    index = (daysBetween(anchor, date) - sum(applied.days)) mod slots.length
    slot = slots[index]
  plan = slot.planId, if active; otherwise rest
dayPlans(date):
  base = planFor(date) minus exceptions(date, plan) where the plan matches
  plus moved-in = exceptions where movedToDate == date and planFor(e.date) == e.planId
```

Status je geplantem Training: `done` (Training aus Plan am Tag beendet), `missed` (Vergangenheit, kein Training am Tag), `insteadOf` (Vergangenheit, anderes Training beendet), `planned`. `mod` ist nicht negativ. Datumsrechnung erfolgt mit lokalen Kalendertagen, nicht mit 24-Stunden-Dauern, damit Sommerzeitwechsel keinen Tag verschieben. Tests decken auch einen Ankertag vor einem Sommerzeitwechsel ab.

### D3 – Sync und Backend

- `ResourceKind.TrainingSchedule` ersetzt den Wert 5 nicht. Es bekommt einen neuen Wert, `WorkoutRotation = 5` wird entfernt und nicht wiederverwendet.
- Mutationen:
  - `SaveTrainingScheduleMutation(scheduleId, baseVersion, mode, anchorDate, validFrom, slots, shifts, exceptions)`
  - `DeleteTrainingScheduleMutation(scheduleId, baseVersion)`
- `TrainingScheduleValidation` prüft:
  - Slot-Regeln je Modus
  - mindestens ein Plan
  - Pläne gehören dem Nutzer (Abfrage gefiltert nach `UserId`)
  - `Days` 1–31
  - höchstens 1000 Verschiebungen und Ausnahmen
  - eindeutige `(Date, PlanId)` je Ausnahme
- Archivierte Pläne sind beim Speichern erlaubt, weil ein Plan nach dem Anlegen des Rhythmus archiviert werden kann.
- Fehler laufen über die bestehenden Abbildungen im `SyncMutationsController` (Validierung, Konflikt, nicht gefunden).
- Die EF-Migration löscht `WorkoutRotations` und `WorkoutRotationItems` und legt vier neue Tabellen an, alle mit `UserId` und Index. Danach `dotnet format`.
- Der Client fasst Mutationen zusammen (ein wartender Stand je Ressource) und sendet Pläne vor dem Rhythmus.

### D3a – Wire-Vertrag (verbindlich für Backend und App)

- Ressourcentyp im Sync: `TrainingSchedule`. Lokaler Typ: `training-schedule`.
- Operationen: `saveTrainingSchedule` und `deleteTrainingSchedule`.
- Datumsfelder sind lokale Kalendertage als `"YYYY-MM-DD"`. Plan-IDs sind UUID-Strings.

Payload `saveTrainingSchedule`:

```json
{
  "scheduleId": "uuid",
  "baseVersion": 0,
  "mode": "cycle",
  "anchorDate": "2026-10-20",
  "validFrom": "2026-10-21",
  "slots": [{ "planId": "uuid" }, { "planId": null }],
  "shifts": [{ "fromDate": "2026-10-23", "days": 1 }],
  "exceptions": [{ "date": "2026-10-22", "planId": "uuid", "movedToDate": "2026-10-23" }]
}
```

- `mode` ist `"cycle"` oder `"weekly"`.
- `anchorDate` ist bei `weekly` `null`.
- Die Position eines Slots ist sein Index. Bei `weekly` ist Index 0 der Montag.
- `movedToDate: null` heißt übersprungen.

Payload `deleteTrainingSchedule`: `{ "scheduleId": "uuid", "baseVersion": 3 }`.

Der Snapshot vom Server (Pull und Mutationsantwort) hat dieselben Felder ohne `baseVersion`, zusätzlich `updatedAtUtc` und `version`. Die lokale Arbeitskopie in `LocalResources` hat dieselbe Form wie der Snapshot.

### D4 – Lokales Upgrade

Die Drift-Schema-Version wird erhöht. Der Upgrade-Schritt löscht `LocalResources` vom Typ `workout-rotation` sowie Outbox-, Konflikt- und Tombstone-Einträge dieser Ressource. Der Rhythmus wird als Typ `training-schedule` gespeichert.

### D5 – Shell und Kalender-UI

- `MobileArea.progress` wird zu `MobileArea.calendar('Kalender', CupertinoIcons.calendar)` und bleibt an erster Stelle.
- `ui/features/calendar/` enthält:
  - `calendar_screen.dart`: großer Titel „Kalender“, Toolbar mit „Heute“ und „…“ (Rhythmus)
  - `calendar_month_grid.dart`
  - `calendar_day_view.dart`
  - `calendar_view_model.dart`
- Das ViewModel liest einen Monat (sichtbare Wochen) in einem Durchlauf aus den lokalen Repositories und hält ihn im Speicher. Neu geladen wird bei Tab-Wechsel, Sync-Ende und Rückkehr aus einem Screen.
- Die Inhalte von `ProgressScreen` werden in Widgets zerlegt und nur für heute in der Tagesansicht genutzt. `ProgressViewModel` bleibt für Dashboard-Daten bestehen.
- Markierungen sind Punkte unter der Tageszahl. Erledigt ist gefüllt, geplant ist ein Ring, verpasst ist ein Ring in Warnfarbe. Die Beschriftung für VoiceOver nennt alle Markierungen.
- Bei Textgröße 2 schrumpft das Raster auf Punkte ohne Wochentagskürzel-Überlauf. Ein Golden-Test deckt das ab.

### D6 – Rhythmus-Editor

Sheet mit Griff und Segment „Zyklus | Feste Tage“.

- **Zyklus:** Liste der Slots mit Ziehgriffen, Wischen zum Löschen, „+ Plan“ und „+ Ruhetag“, darunter „Heute ist: <Slot>“.
- **Feste Tage:** sieben Zeilen Mo–So mit Auswahl von Plan oder Ruhetag.
- Unten steht eine Vorschau der nächsten 14 Tage.
- „Rhythmus löschen“ steht im Kontextmenü.

### D7 – Tagesaktionen

Ein Kontext-Sheet auf der Plan-Karte bietet nur die zulässigen Aktionen nach `training-schedule`:

- „Verschieben…“ öffnet die Wahl „Rhythmus +1 / +2 Tage“ (nur Zyklus) und „Nur dieses auf <Tag>“.
- „Überspringen“
- „Heute nachholen“ und „Ab heute weiter“
- „Aufheben“

Jede Aktion schreibt sofort lokal und erzeugt einen zusammengefassten Outbox-Eintrag.

## Risks / Trade-offs

- **Ausnahmen werden wirkungslos,** wenn der Rhythmus danach verschoben wird. Das ist gewollt und deterministisch, für Nutzer aber eventuell überraschend. Gegenmaßnahme: Vor „Rhythmus verschieben“ weist ein Hinweis darauf hin, wenn danach liegende Ausnahmen betroffen sind.
- **Wachsende Ausnahmeliste:** Die Obergrenze von 1000 reicht für viele Jahre. Später lassen sich Einträge vor `ValidFrom` serverseitig verwerfen.
- **Großer UI-Umbau des Start-Tabs:** Das Risiko sinkt durch zwei PRs (siehe Tasks) und Geräte-Screenshots vor dem Merge.
