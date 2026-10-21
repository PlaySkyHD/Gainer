# Tasks

## PR 1 – Rhythmus statt Rotation

### 1. Backend

- [x] 1.1 `TrainingSchedule`, Slots, Verschiebungen und Ausnahmen in `Gainer.Core/Training`; Mutationen Speichern/Löschen; `TrainingScheduleValidation` (D1, D3). Dazu Unit-Tests der Validierung.
- [x] 1.2 `WorkoutRotation*` entfernen: Core, Queries, `ResourceKind`, Executor, Processor, Controller, DI. Die bestehenden Tests darauf umstellen.
- [x] 1.3 EF-Migration (Rotation löschen, Rhythmus anlegen) mit `dotnet format`. Contracts und Handler.
- [x] 1.4 Integrationstests mit zwei Nutzern:
  - Speichern, Versionskonflikt, idempotente Wiederholung
  - fremder Plan wird abgelehnt
  - Löschen
  - `SaveWorkoutRotation` wird als unbekannt abgelehnt

### 2. Flutter-Daten

- [x] 2.1 `training_schedule.dart` mit Vorschau und Status (D2). Unit-Tests für alle Spec-Szenarien, Sommerzeit und negativen Index.
- [x] 2.2 Repository: Rhythmus lesen und speichern, Tagesaktionen, zusammengefasste Outbox, Pläne vor dem Rhythmus senden. Codec-Tests.
- [x] 2.3 Drift-Upgrade, das Rotationsdaten verwirft (D4). Migrationstest mit gemischter Outbox.

### 3. Flutter-UI Training

- [x] 3.1 Rhythmus-Editor (D6) mit Widget-Tests und Goldens, auch bei Textgröße 2.
- [x] 3.2 Karte „Heute“ im Trainings-Tab. Button „Rhythmus“ ersetzt „Rotation“, `plan_rotation_sheet.dart` entfernen. Widget-Tests.

### 4. Abschluss PR 1

- [ ] 4.1 `openspec validate add-training-calendar --strict`, `flutter analyze`, `flutter test`, Format-Check, Vorschau über `tool/preview_goldens.sh`.
- [ ] 4.2 PR, CI grün, Merge, TestFlight.

## PR 2 – Kalender-Tab

### 5. Kalender

- [x] 5.1 `MobileArea.calendar` ersetzt `progress` (D5). `scripts/Verify-Mobile.ps1` anpassen.
- [x] 5.2 `CalendarViewModel`: Monat aus lokalen Repositories laden (Training, Cardio, Ernährung, Check-in, Rhythmus). Neu laden nach Sync und Tab-Wechsel. Unit-Tests.
- [x] 5.3 Monatsraster mit Markierungen, Wischen, „Heute“ und VoiceOver-Beschriftung. Goldens, auch bei Textgröße 2.
- [x] 5.4 Tagesansicht mit Plan-Karte und Tagesaktionen (D7), Training, Ernährung und Check-in mit Navigation in die Tabs. Für heute kommen die Heute-Inhalte dazu. Widget-Tests.
- [x] 5.5 Essen- und Check-in-Tab lassen sich mit einem Tag öffnen, falls das noch nicht geht.

### 6. Abschluss PR 2

- [ ] 6.1 Prüfungen wie 4.1, Geräte-Screenshots, PR, Merge, TestFlight.
- [ ] 6.2 Abnahme auf dem iPhone:
  - offline überspringen und verschieben, dann sync
  - Training beenden, danach Kalender aktuell
  - Wechsel von Sommer- auf Winterzeit
