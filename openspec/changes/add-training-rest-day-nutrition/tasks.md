# Tasks

Ein PR auf einem Feature-Branch. Commits nach Conventional Commits. Nach jedem Abschnitt laufen Build und Tests grün.

## 1. Backend

- [x] 1.1 Ruhetag-Ziel an `NutritionTargetVersion` und `NutritionTargetVersionDraft` (D2). Die Validierung je Makro-Set wird extrahiert und für beide Sets aufgerufen. Unit-Tests:
  - vollständiges Ruhetag-Ziel
  - unvollständiges Ruhetag-Ziel
  - Prozent-Summe ≠ 100
  - Energie-Abweichung
  - ohne Ruhetag-Ziel unverändert
- [x] 1.2 Neue Regeln im `NutritionTargetScheduleMutationHandler` (D4). Integrationstests für jede Regel:
  - Ende der Vorversion auf `S - 1` setzen
  - zweite Änderung am selben Tag
  - offline gemachte Änderung, Tage später gesendet
  - geänderte Version vor `S` wird abgelehnt
  - neue Version vor einer begonnenen Version wird abgelehnt
  - alte geplante Phase verwerfen
  - Ablauf eines alten Clients („Ende heute, neu ab morgen“)
- [x] 1.3 `NutritionDayKind` und `NutritionDay.DayKind`, optionaler Parameter in `SaveNutritionDayMutation.Create` (D5). Unit-Test für eine unbekannte Tagesart.
- [x] 1.4 EF-Migration mit nullbaren Spalten, danach `dotnet format`. Executor, Snapshots und Queries übernehmen die neuen Felder.
- [x] 1.5 Contracts mit nachgestellten, optionalen Feldern (D8), OpenAPI neu erzeugen. Die Kompatibilitätsprüfung bleibt grün.
- [x] 1.6 Integrationstests (`sg docker -c 'dotnet test …'`) mit zwei Nutzern:
  - Ziele mit Ruhetag-Ziel speichern und per Pull lesen
  - Tag mit Tagesart, auch ohne Einträge
  - Versionskonflikt
  - idempotente Wiederholung derselben Mutation-ID
  - Mutation ohne neue Felder wird angenommen
  - Tagesart „Refeed“ wird abgelehnt
  - Nutzer B sieht keine Daten von Nutzer A

## 2. Flutter-Domäne und Daten

- [x] 2.1 `NutritionDayTarget`, `NutritionTargetVersion.restDay` und `NutritionDay.dayKind` mit JSON und Validierung. Unit-Tests.
- [x] 2.2 `NutritionRepository.saveTargets` (D3) ersetzt `addTargetPhase`, `updateTargetPhase` und `removeTargetPhase`. Unit-Tests:
  - erste Ziele
  - Änderung an einem späteren Tag kürzt die Vorversion
  - zweite Änderung am selben Tag ersetzt die Version
  - alte Daten mit geschlossener laufender und geplanter Folgephase
  - Ruhetag-Ziel ausschalten
  - Spec-Szenario „Ruhetag-Ziel nachträglich einführen“
- [x] 2.3 `TrainingScheduleProjection.hasFinishedOn` sowie `automaticDayKind` und `dayTarget` in `domain/models/nutrition/day_target.dart` (D6). Unit-Tests decken alle Szenarien aus „Tagesart automatisch bestimmen“ und „Ziel eines Tages“ ab, außerdem Versionswechsel, Cardio ohne Einfluss und gelöschte Trainings.
- [x] 2.4 Codec: `restDay` und `dayKind` nur senden, wenn gesetzt, und aus Snapshots lesen. Codec-Tests für mit und ohne Felder.
- [x] 2.5 `NutritionRepository.setDayKind` mit zusammengefasster Outbox. Gemeinsames Lese-Interface für die Projektionseingaben (D7). Tests:
  - offline festlegen und Mahlzeit erfassen ergibt einen wartenden Stand
  - Aufheben setzt `dayKind` auf null, ohne den Tag zu löschen
- [x] 2.6 Durchschnitte nutzen `dayTarget`. Unit-Test mit dem Spec-Beispiel: Ø 2.466,67 kcal, angezeigt „2.467 kcal“, 2 von 3 Tagen im Zielbereich.

## 3. Flutter-UI

- [x] 3.1 Bereich „Ziele“ und Ziel-Editor (D9) ersetzen die Phasen-UI. Phasenzeile, Phasen-Editor, Kategorie-Auswahl und Entfernen-Dialog werden entfernt. Widget-Tests:
  - Ziele anlegen
  - Ruhetag-Ziel ausschalten
  - deaktiviertes Speichern bei ungültigem Ruhetag-Ziel
  - Hinweis „Rhythmus einrichten“ ohne Rhythmus

  Goldens hell und dunkel, auch bei Textgröße 2.
- [x] 3.2 Tageskarte im Tab „Essen“: Chip für die Tagesart statt Phasenname und Kategorie, Sheet „Zählt als“, neu laden bei Tab-Wechsel und Sync-Ende. Widget-Tests:
  - Ruhetag-Ziel wird angezeigt
  - manuelle Festlegung und „Automatisch“
  - ohne Ruhetag-Ziel kein Chip
  - ohne Ziele „Ziele festlegen“
  - Überspringen im Kalender, dann wechselt der Tab „Essen“ auf das Ruhetag-Ziel
- [x] 3.3 Ernährungskarte im Kalender mit Chip und Sheet, „Ruhetag · manuell“. Goldens aktualisieren, Widget-Test für einen vergangenen Tag mit Festlegung.
- [x] 3.4 VoiceOver-Beschriftung des Chips, Test über Semantics.

## 4. Tagesvorlagen

- [x] 4.1 Backend:
  - `NutritionDayTemplate` mit Einträgen und `ResourceKind.NutritionDayTemplate = 13`
  - Mutationen speichern und löschen, Handler, Executor, Processor, Snapshots und Pull, Contracts (D10)
  - Tabellen in der EF-Migration aus 1.4
- [x] 4.2 Integrationstests mit zwei Nutzern:
  - speichern, überschreiben, löschen
  - Versionskonflikt
  - idempotente Wiederholung
  - Validierung: Name, 201 Einträge, doppelte IDs, Tagesart
  - Obergrenze von 50
  - fremde Vorlage löschen ergibt „nicht gefunden“
- [x] 4.3 Flutter-Modell, Codec und Konflikt-Abbildung für `nutrition-day-template`. Codec-Tests.
- [x] 4.4 Repository (D11): `saveDayAsTemplate`, `applyTemplate` (Ersetzen und Hinzufügen), `deleteTemplate`, `updateTemplateMeta`, `suggestedTemplate`. Unit-Tests für alle Szenarien aus `nutrition-day-templates`:
  - Kopien mit neuen IDs
  - manuelle Tagesart bleibt erhalten
  - Grenze von 200 Einträgen
  - offline speichern und anwenden
- [x] 4.5 UI (D12): Tagesmenü, Sheets „Als Vorlage speichern“ und „Aus Vorlage befüllen“, Ersetzen/Hinzufügen-Abfrage, Vorschlag in der leeren Tageskarte, Bereich „Tagesvorlagen“ mit Detailansicht und Wischen zum Löschen. Widget-Tests und Goldens hell, dunkel und bei Textgröße 2.

## 5. Abschluss

- [x] 5.1 Lokal prüfen:
  - `openspec validate add-training-rest-day-nutrition --strict`
  - `flutter analyze`, `flutter test`, Format-Check
  - `dotnet build`, `dotnet test` (über `sg docker`)
  - lesbare Vorschau mit `tool/preview_goldens.sh`
- [ ] 5.2 PR (Hinweis auf ältere App-Stände und entfernte Phasen-UI), CI grün, Merge, TestFlight.
- [ ] 5.3 Abnahme auf dem iPhone:
  - bestehende Ziele erscheinen unter „Ziele“
  - Ruhetag-Ziel ergänzen; gestrige Werte bleiben unverändert
  - Ruhetag und Trainingstag im Essen-Tab und im Kalender prüfen
  - offline einen Tag festlegen und Ziele ändern, nach Wiederverbindung den Serverstand prüfen
  - ein Training überspringen und prüfen, dass das Ziel wechselt
  - heute als Vorlage „Trainingstag“ speichern, auf morgen anwenden, mit „Ersetzen“ und „Hinzufügen“ testen
  - Vorlage überschreiben; bereits befüllte Tage bleiben unverändert
  - Vorschlag an einem leeren Ruhetag
