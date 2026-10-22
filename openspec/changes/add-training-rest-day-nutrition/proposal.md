# Proposal

## Why

Viele Nutzer essen nach festem Plan, mit unterschiedlichen Makros an Trainings- und an Ruhetagen. Die App kennt bisher nur ein Makro-Set pro Tag, verpackt in benannte Zielphasen mit Kategorie und Zeitraum. Laut Nutzer verwendet niemand diese Phasen. Außerdem sind begonnene Phasen schreibgeschützt, sodass sich das aktuelle Ziel nicht einfach ändern lässt.

Wer nach festem Plan isst, trägt außerdem jeden Tag dieselben Lebensmittel neu ein. Bisher lassen sich nur einzelne Mahlzeiten speichern, kein ganzer Tag.

Seit `add-training-calendar` weiß die App, ob an einem Tag ein Training geplant oder erledigt ist. Diese Information lässt sich jetzt für die Ernährungsziele nutzen.

## What Changes

- **Zielphasen werden zu einfachen Zielen.** Im Tab „Essen“ gibt es nur noch „Ziele“ mit zwei Blöcken:
  - **Trainingstag:** kcal, Eingabemodus (Gramm oder Prozent), Protein, Kohlenhydrate, Fett.
  - **Ruhetag:** optional, mit denselben Feldern.
  - Dazu kommt eine gemeinsame Salzobergrenze.

  Name, Kategorie (Cut, Erhalt, Aufbau), Zeiträume und die Phasenliste entfallen in der UI. **BREAKING (UI)**
- **Jederzeit bearbeiten, gültig ab heute.** Jede Änderung legt im Hintergrund eine neue Zielversion ab dem heutigen lokalen Tag an. Vergangene Tage behalten das Ziel, das damals galt. Eine zweite Änderung am selben Tag überschreibt die Version von heute.
- **Server-Regeln für Zielversionen gelockert.** Eine Mutation darf alles ab dem Beginn ihrer neuesten Version ändern, davor aber nichts. Die einzige Ausnahme ist das Ende der vorherigen Version. Der Bezug auf das UTC-Datum des Servers entfällt dabei weitgehend, damit offline gemachte Änderungen auch Tage später noch synchronisiert werden.
- **Tagesart automatisch bestimmen.** Ein Tag zählt als **Trainingstag**, wenn ein Krafttraining beendet wurde oder laut Rhythmus eines ansteht. Das gilt auch für verpasste und dorthin verschobene Trainings. Sonst ist er ein **Ruhetag**.
- **Tagesart manuell festlegen.** In der Ernährungs-Tagesansicht und in der Kalender-Tagesansicht kann der Nutzer für jeden Tag „Zählt als: Automatisch | Trainingstag | Ruhetag“ wählen. Die Wahl ändert nur das Ernährungsziel, nicht den Rhythmus.
- **Anzeige.** Die Tageskarte im Tab „Essen“, die Ernährungskarte im Kalender und die Durchschnitte nutzen das Ziel der jeweiligen Tagesart. Sie beschriften es mit „Trainingstag“ bzw. „Ruhetag“ statt mit Phasenname und Kategorie.

- **Tagesvorlagen.**
  - **Speichern:** Ein Ernährungstag lässt sich mit allen Einträgen als benannte Vorlage speichern (z. B. „Trainingstag“), oder er überschreibt eine bestehende Vorlage.
  - **Anwenden:** Eine Vorlage lässt sich auf jeden Tag anwenden. Hat der Tag schon Einträge, fragt die App „Ersetzen“ oder „Hinzufügen“.
  - **Tagesart:** Eine Vorlage kann optional für Trainings- oder Ruhetage markiert sein. An einem leeren Tag schlägt die App dann die passende Vorlage vor.
  - **Unabhängigkeit:** Angewendete Einträge sind Kopien. Spätere Änderungen an der Vorlage ändern keine Tage.

### Non-Goals

- **Eigene Ziele pro Trainingsplan**, z. B. ein höheres Ziel für den Beintag (spätere Phase).
- Mehr als zwei Tagesarten oder frei benannte Tagestypen.
- Einzelne Einträge einer Tagesvorlage direkt bearbeiten. Stattdessen wendet man die Vorlage auf einen Tag an, ändert ihn und überschreibt die Vorlage.
- Vorlagen automatisch anwenden, ohne dass der Nutzer es bestätigt.
- Vorlagen mit Portionsfaktor skalieren.
- Ziele im Voraus für ein künftiges Datum planen. Das konnten Phasen bisher, dafür gibt es aber keinen Bedarf.
- Ziele vollständig entfernen. Man kann das Ruhetag-Ziel ausschalten, aber nicht „gar kein Ziel“ ab heute setzen.
- Cardio als Grund für einen Trainingstag.
- Die Tagesart im Backend berechnen. `GET nutrition/days/{date}` und `GET nutrition/targets/effective/{date}` liefern weiterhin das Trainingstag-Ziel. Die App nutzt diese Endpunkte für die Anzeige nicht.
- Automatische oder AI-gestützte Zielvorschläge.

## Capabilities

### New Capabilities

- `training-day-nutrition-targets`: einfache Ziele für Trainings- und Ruhetag, Versionierung im Hintergrund, Bestimmung und manuelle Festlegung der Tagesart, Nutzung in Tageskarte, Kalender und Durchschnitten sowie Speicherung und Sync.

- `nutrition-day-templates`: Tagesvorlagen speichern, überschreiben, anwenden, vorschlagen und verwalten, mit Sync.

### Modified Capabilities

Keine unter `openspec/specs/`. Inhaltlich ersetzt dieser Change aus `nutrition-targets` (Change `add-smart-meals-and-nutrition-targets`, nicht archiviert) zwei Teile:
- „Benannte und zeitlich wirksame Ernährungszielphasen verwalten“ samt der Unveränderlichkeit begonnener Phasen
- in „Zugänglicher Tagesfortschritt“ die Anzeige von Phasenname und Kategorie

Beim Archivieren wird `nutrition-targets` entsprechend angepasst. Die übrigen Anforderungen, also Makro-Energiebilanz, Fortschrittsdarstellung, Offline-Sync und Nutzerisolation, gelten weiter.

## Kernjourney

Gehört zur privaten Kernjourney (Ernährung erfassen und mit Ziel vergleichen). Die Non-Goals sind spätere Phasen.

## Breaking Changes

- **UI:** Phasenliste, Phasenname, Kategorie und „Zielphase hinzufügen“ entfallen.
- **Bestehende Daten** bleiben erhalten und werden zu unsichtbarer Historie.
  - Die laufende offene Version erscheint als „Ziele“.
  - Künftige Versionen werden bei der ersten Bearbeitung verworfen.
  - Eine Migration der Daten ist nicht nötig.
- **Contracts:** keine Breaking Changes, alle neuen Felder sind optional. Neu angelegte Versionen haben den Namen „Ziele“ und die Kategorie `Custom`.
- **Server-Regeln:** Was der Server bisher annahm, nimmt er weiterhin an, er erlaubt jetzt nur zusätzlich mehr. Ältere App-Versionen funktionieren also weiter. Sie senden aber den vollständigen Stand ohne Ruhetag-Ziel und Tagesart:
  - Das Ruhetag-Ziel der aktuellen Version wird überschrieben, wenn ein alter Client sie ändert.
  - Eine manuelle Tagesart wird verworfen.

  Das wird akzeptiert, weil es pro Nutzer ein Schreibgerät gibt und Updates über TestFlight laufen.

## Security

- Tagesvorlagen sind eine neue nutzerbezogene Ressource mit `UserId`. Die API leitet den Nutzer aus der Sitzung ab. Lesen, Ändern und Löschen fremder Vorlagen ist nicht möglich, was mit zwei Testnutzern geprüft wird.

- Ziele und Tagesart gehören zu bestehenden nutzerbezogenen Aggregaten (`NutritionTargetSchedule`, `NutritionDay`) mit `UserId`. Es gibt keine neuen Endpunkte außerhalb des Sync-Vertrags.
- Der Server prüft die neuen Felder wie die bestehenden Zielwerte: Wertebereiche, Prozent-Summe 100 und eine Tagesart aus festen Werten.
- Die gelockerten Regeln betreffen nur Daten des angemeldeten Nutzers. Tage vor dem Beginn einer Änderung bleiben unveränderlich.
- Es gibt keine AI-Beteiligung.

## Impact

- **Backend:**
  - `Gainer.Core/Nutrition/NutritionTargets.cs`: Ruhetag-Felder und Validierung.
  - `NutritionModels.cs` und `NutritionMutations.cs`: `DayKind` am Ernährungstag.
  - `NutritionTargetScheduleMutationHandler`: neue Regeln für Abschluss, Änderung in place und Startdatum.
  - `SyncMutationExecutor`, `SmartNutritionSnapshots`, `SmartNutritionQueries`, Tages-Snapshots.
  - `AppDbContext` und eine EF-Migration mit nullbaren Spalten.
- **Tagesvorlagen im Backend:**
  - neu `Gainer.Core/Nutrition/NutritionDayTemplates.cs`
  - `ResourceKind.NutritionDayTemplate`
  - Mutationen speichern und löschen
  - `NutritionDayTemplateMutationHandler`
  - Executor, Processor, Snapshots und Pull
  - Tabellen in derselben EF-Migration
- **Contracts:** `NutritionContracts.cs` und `contracts/openapi/Gainer.Api.json`, jeweils mit optionalen Feldern.
- **Flutter:**
  - Domäne:
    - `nutrition.dart`: `NutritionDayTarget`, `restDay` und `dayKind`.
    - neue Datei `day_target.dart`.
    - `nutrition_averages.dart` und `training_schedule.dart` (Abfrage beendeter Trainings).
  - Daten:
    - `nutrition_repository.dart`: `saveTargets` ersetzt `addTargetPhase`, `updateTargetPhase` und `removeTargetPhase`; dazu `setDayKind`.
    - `sync_payload_codec.dart`.
  - UI:
    - `nutrition_screen_cupertino.dart`: Phasen-UI raus, Ziel-Editor und Tagesart-Chip rein.
    - `nutrition_view_model.dart`.
    - Kalender: `calendar_view_model.dart`, `calendar_day_view.dart`, `calendar_nutrition_overview.dart`.
    - `nutrition_averages_view.dart`.
- **Tagesvorlagen in Flutter:**
  - Domänenmodell `NutritionDayTemplate`
  - Repository-Methoden `saveDayAsTemplate`, `applyTemplate` und `deleteTemplate`
  - lokaler Typ `nutrition-day-template` im Codec und in `local_conflict_recovery.dart`
  - UI im Tab „Essen“: Aktionen im Tagesmenü, Sheets, Vorschlag und Verwaltungsliste
- **Tests:**
  - Dart-Unit-Tests für Tagesart, Tagesziel und Versionierung.
  - Codec-Tests.
  - C#-Integrationstests für die neuen Regeln, Validierung, Isolation und Rückwärtskompatibilität.
  - Goldens für Editor, Tageskarte und Kalenderkarte, auch bei Textgröße 2.
