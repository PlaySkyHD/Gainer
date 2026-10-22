# Design

## Context

Motivation und Umfang stehen in `proposal.md`, das Verhalten in `specs/training-day-nutrition-targets`.

Ist-Zustand:

- **Zielphasen im Backend:** `NutritionTargetSchedule` mit `NutritionTargetVersion`s (`Gainer.Core/Nutrition/NutritionTargets.cs`). Gespeichert wird als vollständiger Stand über `saveNutritionTargetSchedule`. Der `NutritionTargetScheduleMutationHandler` verhindert Änderungen an Versionen mit `EffectiveFrom <= today`, wobei `today` das UTC-Datum des Servers ist. Er erlaubt nur:
  - eine offene Version zu beenden, wenn das Ende nicht vor heute liegt und eine Folgeversion am nächsten Tag beginnt (`CanCloseOpenPhase`)
  - neue Versionen ab heute (`AddNewVersions`)
- **Zielphasen in Flutter:**
  - `NutritionTargetVersion`/`NutritionTargetSchedule` in `domain/models/nutrition/nutrition.dart`.
  - `NutritionTargetSchedule.targetOn(date)` ist die gemeinsame Abfrage für Tageskarte, Kalender (`calendar_view_model.dart`) und Durchschnitte (`nutrition_averages.dart`).
  - Das Repository bietet `addTargetPhase`, `updateTargetPhase` (nur künftige) und `removeTargetPhase` (nur künftige).
  - Die UI besteht aus `_TargetPhaseRow`, `_TargetPhaseDraft` und dem Phasen-Editor in `nutrition_screen_cupertino.dart`. Kategorie und Name werden nur dort verwendet.
- **Ernährungstag:** `NutritionDay` hat `LocalDate` und `Entries`. `saveNutritionDay` überträgt den vollständigen Stand, leere Einträge sind erlaubt.
- **Rhythmus:** `TrainingScheduleProjection` in `domain/models/training/training_schedule.dart` ist eine reine Funktion, nur auf dem Gerät. `ScheduleDay.effective` enthält die Trainings ohne `moved` und `skipped`. Beendete Trainings werden nach lokalem Starttag gruppiert.

## Goals / Non-Goals

**Goals:**

- Für den Nutzer gibt es nur „Ziele“, die Historie bleibt aber intern korrekt.
- Das Tagesziel ist eine reine, deterministische Dart-Funktion, vollständig unit-testbar.
- Es gibt keine neue Ressource und keinen neuen Sync-Typ.
- Es gibt keine Datenmigration, bestehende Phasen werden zu Historie.

**Non-Goals:** siehe `proposal.md`.

## Decisions

### D1 – Versionen bleiben, die UI zeigt nur die aktuelle

Das Datenmodell `NutritionTargetSchedule` → `Versions` bleibt bestehen. Eine Version entspricht einem Stand der Ziele ab einem Tag.

- `Name` und `Category` bleiben im Schema, damit sich Contracts und alte Daten nicht ändern. Neue Versionen bekommen den Namen `"Ziele"` und die Kategorie `Custom`.
- **„Aktuelle Ziele“** sind die Version mit `targetOn(heute)`. Gibt es keine, gibt es keine Ziele.

*Alternative:* Versionen abschaffen und nur ein Zielobjekt speichern. Verworfen, weil sonst Durchschnitte und Kalender vergangene Tage rückwirkend gegen neue Ziele bewerten würden.

### D2 – Ruhetag-Ziel als optionales Unterobjekt

**Flutter:**
- `NutritionTargetVersion.restDay` vom Typ `NutritionDayTarget?`.
- `NutritionDayTarget` bündelt `inputMode`, `kilocalories`, `proteinGrams`, `carbohydrateGrams`, `fatGrams` sowie `proteinPercent`, `carbohydratePercent` und `fatPercent`.
- Die bestehenden Felder der Version bilden das Trainingstag-Ziel.

**Backend:**
- Nullbare Spalten an `NutritionTargetVersions`: `RestInputMode`, `RestKilocalories`, `RestProteinGrams`, `RestCarbohydrateGrams`, `RestFatGrams`, `RestProteinPercent`, `RestCarbohydratePercent`, `RestFatPercent`.
- Ein Ruhetag-Ziel gibt es genau dann, wenn `RestKilocalories` gesetzt ist.
- Die bestehende Validierung je Makro-Set wird extrahiert und für beide Sets aufgerufen.

*Alternative:* Kind-Tabelle `NutritionTargetVariants`. Verworfen, solange es genau eine Variante gibt. Kommen später Ziele pro Plan dazu, wandern die Spalten in eine Kind-Tabelle.

### D3 – Speichern ab heute (Flutter, `NutritionRepository.saveTargets`)

```
saveTargets(training, restDay?, saltGrams?):
  today = lokaler Tag
  versions = schedule.versions ohne Versionen mit effectiveFrom > today
  current = Version, die today abdeckt (targetOn(today))
  if current != null && current.effectiveFrom == today:
    ersetze current durch eine Kopie mit den neuen Werten (gleiche ID, until = null)
  else:
    if current != null: current.effectiveUntil = today - 1
    füge neue Version (neue ID, effectiveFrom = today, until = null,
                       name "Ziele", category custom) hinzu
  saveTargetSchedule(versions)
```

- `addTargetPhase`, `updateTargetPhase` und `removeTargetPhase` entfallen samt UI.
- Der lokale Tag wird beim Speichern festgelegt. Wird später synchronisiert, bleibt das Datum gleich.
- Alte Daten mit einer geschlossenen laufenden Phase und einer geplanten Folgephase werden so bereinigt:
  - Die laufende Phase wird auf gestern gekürzt.
  - Die geplante Folgephase wird verworfen.

### D4 – Neue Regeln im `NutritionTargetScheduleMutationHandler`

`S` ist der Beginn der neuesten eingehenden Version, also der Tag, ab dem die Mutation etwas ändert. Für gespeicherte Versionen gilt:

1. Eine Version, die vor `S - 1` endet, MUST unverändert mitgeschickt werden.
2. Die Version, die den Tag `S - 1` abdeckt, MUST bis auf `EffectiveUntil` unverändert bleiben. Ihr Ende darf auf `S - 1` gesetzt werden.
3. Eine Version, die genau an `S` beginnt, darf in allen Feldern außer `EffectiveFrom` geändert werden. Das ist die zweite Änderung am selben Tag.
4. Eine Version, die nach `S` beginnt, darf nur entfernt werden, wenn sie nach dem morgigen UTC-Tag des Servers beginnt. Das betrifft nur alte, noch nicht begonnene Planungen. Sonst ist das ein Konflikt.
5. Jeder andere Unterschied ist ein Konflikt, z. B. ein fehlender oder geänderter Tag vor `S`.

Die bestehende Prüfung auf Überschneidungen bleibt.

**Folgen:**
- Weil sich die Regeln an `S` orientieren statt am heutigen Server-Datum, nimmt der Server Offline-Änderungen auch Tage später an.
- Das Server-Datum zählt nur noch in Regel 4. Dort schützt es begonnene Daten davor, durch ein zu frühes `S` entfernt zu werden.

**Was alte Clients senden:**
- „Offene Phase endet heute, neue Phase ab morgen“ erfüllt die Regeln 2 und 3 mit `S` = morgen und funktioniert weiter.
- Ein Stand ohne Ruhetag-Felder ändert die Version, die an `S` beginnt. Das ist erlaubt und überschreibt ihr Ruhetag-Ziel. Diesen Fall nennt das Proposal als akzeptiertes Risiko.

**Sicherheit:** Alle Abfragen bleiben nach `UserId` gefiltert.

### D5 – Tagesart am Ernährungstag

**Flutter:**
- `NutritionDay.dayKind` vom Typ `NutritionDayKind?` mit den Werten `training` und `rest`.
- `null` bedeutet automatisch.

**Backend:**
- `NutritionDay.DayKind`, gespeichert als nullbarer `int`.
- Optionaler Parameter in `SaveNutritionDayMutation.Create`.

Eine Festlegung an einem Tag ohne Einträge legt einen Ernährungstag mit leerer Liste an. Hebt der Nutzer sie auf, wird nur `dayKind` auf `null` gesetzt.

*Alternative:* Festlegung als Ausnahme im Rhythmus speichern. Verworfen, weil sie ohne Rhythmus nicht ginge und den Rhythmus-Vertrag ändern würde.

### D6 – Tagesart und Tagesziel (Dart, `domain/models/nutrition/day_target.dart`)

```
automaticDayKind(date, projection):
  if projection.hasFinishedOn(date): training
  if projection.day(date).effective.isNotEmpty: training
  return rest

dayTarget(date, targets, day, projection):
  version = targets?.targetOn(date)
  if version == null: return null
  if version.restDay == null: return (version.training, kind: null, manual: false)
  kind = day?.dayKind ?? automaticDayKind(date, projection)
  return (kind == rest ? version.restDay : version.training, kind, manual: day?.dayKind != null)
```

- `TrainingScheduleProjection.hasFinishedOn(LocalDay)` wird öffentlich. Es greift auf die schon gruppierten beendeten Trainings zu und funktioniert auch mit `schedule == null`.
- Das Ergebnis `NutritionDayTargetResult(target, kind, manual)` hat dieselben Zielfelder wie bisher. Der Fortschrittscode bleibt deshalb unverändert. Die Salzgrenze kommt aus der Version.

### D7 – Datenfluss in der App

- **`NutritionRepository`:** `saveTargets` (D3) und `setDayKind(localDate, NutritionDayKind?)` schreiben atomar mit Outbox und fassen zu einem wartenden Stand je Ressource zusammen. Die Lesepfade dekodieren `restDay` und `dayKind`.
- **Projektionseingaben:** Rhythmus, Pläne und Trainings kommen über ein gemeinsames Lese-Interface aus `training_log_repository.dart`. Kalender, Tab „Essen“ und Durchschnitte nutzen dasselbe.
- **Neu laden** bei Tab-Wechsel, Sync-Ende und Rückkehr aus einem Screen. So macht es der Kalender schon.

### D8 – Sync und Contracts

- **Payload `saveNutritionTargetSchedule`:** pro Version optional `restDay: { inputMode, kilocalories, proteinGrams, carbohydrateGrams, fatGrams, proteinPercent, carbohydratePercent, fatPercent }`. Der Codec sendet es nur, wenn es gesetzt ist.
- **Payload `saveNutritionDay`:** optional `dayKind: "Training" | "Rest"`.
- **Snapshots** enthalten dieselben optionalen Felder.
- **Contracts:**
  - `NutritionTargetVersionResponse` bekommt den nachgestellten Parameter `NutritionDayTargetResponse? RestDay = null`.
  - Der Ernährungstag bekommt `string? DayKind = null`.
  - OpenAPI wird neu erzeugt, die Kompatibilitätsprüfung bleibt grün.
- **Fehler:**
  - ungültiges `dayKind` oder unvollständiges `restDay`: Validierungsfehler
  - Regelverstoß nach D4: Konflikt
  - Beides läuft über die bestehenden Abbildungen im `SyncMutationsController`.

### D9 – UI

**Bereich „Ziele“ im Tab „Essen“** (ersetzt „Zielphasen“):
- Gruppierte Karte mit den Zeilen „Trainingstag · 2.600 kcal · P 180 g · KH 290 g · F 80 g“, „Ruhetag · …“ (falls vorhanden) und „Salz ≤ 6 g“.
- Antippen öffnet den Editor. Ohne Ziele zeigt die Karte stattdessen eine Zeile „Ziele festlegen“.

**Editor (Sheet mit Griff):**
- Gruppe „Trainingstag“ mit Modus, kcal und Makros.
- Schalter „Eigenes Ziel für Ruhetage“ und darunter die Gruppe „Ruhetag“.
- Gruppe „Salz“.
- Fußnote: „Änderungen gelten ab heute.“ Ohne Rhythmus zusätzlich: „Trainingstage kommen aus deinem Rhythmus“ mit Link „Rhythmus einrichten“.
- Bei Textgröße 2 werden Beschriftung und Eingabe gestapelt.
- Die Energie-Abweichung wird wie bisher bestätigt, getrennt je Ziel.

**Entfernen:** `_TargetPhaseRow`, Phasen-Editor, Kategorie-Auswahl, `_categoryIcon`/`_categoryName` und der Dialog „Zielphase entfernen?“.

**Tageskarte:**
- Die Kopfzeile zeigt statt Phasenname und Kategorie einen Chip „Trainingstag“ oder „Ruhetag“, gegebenenfalls mit „· manuell“. Den Chip gibt es nur, wenn ein Ruhetag-Ziel gilt.
- Antippen öffnet das Sheet „Zählt als“ mit „Automatisch (<berechnete Tagesart>)“, „Trainingstag“ und „Ruhetag“.

**Kalender** (`calendar_nutrition_overview.dart`): derselbe Chip und dasselbe Sheet. Ein Tipp auf die Karte öffnet weiterhin den Tab „Essen“.

**Durchschnitte:** `targetKilocalories` je Tag kommt aus `dayTarget`.

**VoiceOver:** Der Chip trägt die Beschriftung „Tagesart: Ruhetag, manuell festgelegt. Ändern“.

### D10 – Tagesvorlage: Datenmodell

**Backend** (`Gainer.Core/Nutrition/NutritionDayTemplates.cs`):

`NutritionDayTemplate`:

| Feld | Bedeutung |
| --- | --- |
| `Id`, `UserId`, `Version`, `CreatedAtUtc`, `UpdatedAtUtc` | wie bei anderen Aggregaten |
| `Name` | 1–80 Zeichen |
| `DayKind` | `NutritionDayKind?`, aus D5 |

`NutritionDayTemplateEntry`:
- Felder wie `NutritionEntry`: `Meal`, `Position`, `ProductName`, `Brand`, `AmountGrams`, `AmountUnit`, `PieceGrams`, `PieceCount`, Nährwerte je Basis inklusive Salz, `Provider`, `Barcode`, `RetrievedAtUtc`.
- Die Validierung wird aus `SaveNutritionDayMutation` übernommen (`ValidateEntries`), höchstens 200 Einträge.

Weitere Teile:
- `ResourceKind.NutritionDayTemplate = 13`.
- Mutationen `SaveNutritionDayTemplateMutation` und `DeleteNutritionDayTemplateMutation`. Kinder werden bei jedem Speichern vollständig ersetzt, wie bei `ReusableMeal`.
- Beim Anlegen prüft der Handler die Obergrenze von 50 Vorlagen pro Nutzer (`NutritionLimits.MaxDayTemplates`).
- Das Löschen ist echt, mit Tombstone wie bei anderen löschbaren Ressourcen. Weil angewendete Einträge Kopien sind, verweist nichts auf die Vorlage.

**Flutter** (`domain/models/nutrition/nutrition.dart`):
- `NutritionDayTemplate(templateId, name, dayKind?, entries, updatedAtUtc)`.
- Die Einträge nutzen dieselbe Form wie `NutritionEntry`, also auch dieselbe JSON-Form. Codec und Validierung lassen sich so wiederverwenden.
- Lokaler Typ `nutrition-day-template`. Neu in `sync_payload_codec.dart` und in der Typ-Abbildung von `local_conflict_recovery.dart`.

*Alternative:* `ReusableMeal` um eine Mahlzeitenzuordnung erweitern. Verworfen, weil Gerichte Portionsfaktor und Archivstatus haben und in der Gerichteliste erscheinen. Eine Tagesvorlage ist fachlich etwas anderes, und ihre Einträge entsprechen 1:1 einem Ernährungstag.

### D11 – Tagesvorlage: Repository und Anwenden

- **`saveDayAsTemplate(localDate, {String? overwriteId, String? name, NutritionDayKind? dayKind})`**
  - Kopiert die Einträge des Tages mit neuen IDs.
  - Mit `overwriteId` bleiben Name und Tagesart der bestehenden Vorlage erhalten.
  - Schreibt atomar mit Outbox.
- **`applyTemplate(templateId, localDate, mode: replace | append)`**
  - Liest den Tag und erzeugt neue Einträge mit neuen IDs.
  - Bei `append` hängt es Positionen je Mahlzeit nach dem Maximum an, wie `copyReusableMealToDay`.
  - Bei `replace` verwirft es die bisherigen Einträge.
  - `dayKind` des Tages bleibt unverändert.
  - Prüft die Grenze von 200 Einträgen vor dem Schreiben.
  - Speichert über `saveDay`, also mit einem zusammengefassten wartenden Stand des Tages.
- **`deleteTemplate(templateId)`** und **`updateTemplateMeta(templateId, name, dayKind)`**.
- **`suggestedTemplate(localDate)`**
  - Nur für heute oder künftige Tage ohne Einträge.
  - Wählt unter den Vorlagen mit `dayKind == automaticDayKind(date)` bzw. der manuellen Festlegung die mit dem jüngsten `updatedAtUtc` (D6).

### D12 – Tagesvorlage: UI

- **Tagesmenü** „…“ in der Toolbar des Tabs „Essen“ mit „Tag als Vorlage speichern“ und „Aus Vorlage befüllen“. Beide Aktionen gibt es nur dort, nicht im Kalender.
- **Sheet „Als Vorlage speichern“:**
  - Segment „Neu | Überschreiben“.
  - Neu: Name und Tagesart (Keine, Trainingstag, Ruhetag).
  - Überschreiben: Liste der Vorlagen, nach Auswahl eine Bestätigung.
  - Bei 50 Vorlagen ist „Neu“ deaktiviert, mit Erklärung.
- **Sheet „Aus Vorlage befüllen“:**
  - Liste mit Name, Tagesart und kcal/Protein.
  - Hat der Tag schon Einträge, fragt danach ein Aktions-Sheet „Ersetzen“, „Hinzufügen“ oder „Abbrechen“.
- **Vorschlag:** eine Zeile in der leeren Tageskarte: „Vorlage „Ruhetag“ übernehmen“ mit Pill-Button.
- **Bereich „Tagesvorlagen“** unter „Gespeicherte Gerichte“:
  - Zeilen mit Name und „Ruhetag · 2.180 kcal · P 175 g“.
  - Antippen zeigt die Einträge nach Mahlzeit, mit Name und Tagesart in der Toolbar bearbeitbar.
  - Wischen löscht nach Bestätigung.
- Alle Sheets haben einen Griff, passende Höhe und Tastaturabstand (`showGainerSheet`). Bei Textgröße 2 wird gestapelt.

## Risks / Trade-offs

- **Ältere App-Stände** überschreiben beim Speichern das Ruhetag-Ziel der offenen Version und manuelle Festlegungen. Das ist akzeptiert, siehe Proposal.
- **Gelockerte Server-Regeln:** Eine Version lässt sich jetzt ab ihrem Beginn ändern, wenn ein Client das sendet. Unsere App macht das nur am Tag ihres Beginns. Für die Sicherheit ist das ohne Belang, weil es nur eigene Daten betrifft. Fachlich ist es ein bewusster Tausch gegen Offline-Fähigkeit.
- **Kein Rhythmus, aber ein Ruhetag-Ziel:** Bis zum Beenden eines Trainings zählt jeder Tag als Ruhetag. Gegenmaßnahme ist der Hinweis im Editor.
- **Training nach Mitternacht** zählt zum Starttag, konsistent mit der Erfüllung im Rhythmus.
- **Vorlagen mit veralteten Nährwerten:** Eine Vorlage speichert die Nährwerte zum Zeitpunkt des Speicherns. Ändern sich Produktdaten, merkt die Vorlage das nicht. Das ist gewollt und entspricht dem Verhalten der Gerichte.
- **Server-Endpunkte** zeigen an Ruhetagen das Trainingstag-Ziel. Die App nutzt sie nicht. Eine spätere AI-Auswertung muss die Tagesart vom Client bekommen oder selbst berechnen.
