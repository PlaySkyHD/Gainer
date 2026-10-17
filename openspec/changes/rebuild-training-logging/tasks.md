# Tasks

Jeder Task benötigt grüne betroffene Builds und Tests, bevor sein Haken gesetzt wird. Commits verwenden Conventional Commits. Nutzerisolation wird in jedem Backend-Task mit mindestens zwei Testnutzern geprüft.

## 1. Planungsgrundlage bereinigen

- [x] 1.1 In `build-ai-body-training-tracker-mvp` die Specs `workout-execution` und `exercise-and-plan-management` sowie die offenen Trainings-Tasks als durch `rebuild-training-logging` abgelöst kennzeichnen; in `migrate-pwa-to-ios-first-flutter` die Requirements „Pausentimer und lokale Benachrichtigungen“ und „Live Activity für Workout und Pause“ ebenso. Prüfen mit `openspec validate --all`, dass alle Changes gültig bleiben.

## 2. Backend: Übungskatalog

- [x] 2.1 `Exercise` um `ExerciseType`, `Notes`, `BodyweightFactor`, `WeightFactor` erweitern; `ExerciseCategory` und Zuordnungstabelle anlegen (D6). Unit-Tests für Typparser (unbekannter Typ → Ablehnung) und Faktor-Defaults gemäß Spec `exercise-catalog` grün.
- [x] 2.2 `ExerciseCatalogSnapshot` als neue Katalogversion um Typ, Basis-Kategorien und Faktoren erweitern; Integrationstest prüft, dass Basisübungen und -kategorien nicht änderbar sind.
- [x] 2.3 Sync-Operationen für eigene Übungen (anlegen/ändern/archivieren inkl. Typ, Kategorien, Faktoren) und eigene Kategorien implementieren; Integrationstests für Idempotenz bei Wiederholung und Zugriff auf fremde IDs (Nutzer A/B, keine Datenoffenlegung).
- [x] 2.4 `ExerciseCatalogController`/`ExerciseCatalogResponse` um Typ, Kategorien und Faktoren erweitern; API-Integrationstest liefert Basis- plus eigene Übungen nur des angemeldeten Nutzers.

## 3. Backend: Workouts und Pläne

- [ ] 3.1 Neues Workout-Modell (D1) und Plan-Modell (D5) in `Gainer.Core/Training` umsetzen, `WorkoutStatus` und `WorkoutHistoryProtectionInterceptor` entfernen; Domänen-Unit-Tests für Validierung (Endzeit > Start, Wertebereiche, Satztyp-Fallback, Mindestsatzzahl je Planeintrag) grün.
- [ ] 3.2 EF-Core-Migration für den Datenneustart (D11) inklusive partiellem Unique-Index „ein aktives Workout pro Nutzer“ erzeugen; Integrationstest gegen PostgreSQL prüft Up-Migration auf einer Datenbank mit Altdaten und das Ablehnen eines zweiten aktiven Workouts.
- [ ] 3.3 `createWorkout`, `saveWorkout` (inkl. Beenden/Fortsetzen über `endedAtUtc`), `deleteWorkout` im `SyncMutationExecutor` mit Handlern implementieren (D2); Integrationstests: leer/aus Plan/aus Wiederholung anlegen, historisches Workout ändern, Löschen erzeugt Tombstone, wiederholte Mutations-ID ohne Doppelwirkung, fremde Workout-/Plan-/Übungs-IDs werden ohne Offenlegung abgelehnt.
- [ ] 3.4 Plan-Operationen (anlegen, ändern, umordnen, archivieren) und Rotation auf Pläne umstellen; Rotationsvorschlag aus jüngstem beendeten, nicht gelöschten Rotations-Workout ableiten (D5). Integrationstests für die Szenarien „Nächster Plan“, „Letztes Training gelöscht“ und „Leere Rotation“.
- [ ] 3.5 `mergeExercises` implementieren (D4); Integrationstest: Referenzen in Workouts und Plänen des Nutzers zeigen auf das Ziel, Namenssnapshots bleiben, Quellübung ist archiviert, fremde Zielübung wird abgelehnt, Wiederholung wirkt genau einmal.
- [ ] 3.6 `WorkoutHistoryQueries` und Change-Feed auf das neue Modell umstellen; `PreviousPerformanceQueries` entfernen, sofern kein Verbraucher bleibt. Integrationstest: Pull liefert neue Workouts, Pläne und Tombstones nur für den eigenen Nutzer.
- [ ] 3.7 Mindest-Clientversion des Sync-Vertrags anheben, sodass alte App-Versionen mit verständlichem Fehler abgewiesen werden; Integrationstest mit alter Clientversion.

## 4. Kennzahlen (Backend)

- [ ] 4.1 Gemeinsame Fixture `contracts/fixtures/training-statistics.json` mit allen Rechenszenarien der Spec `training-statistics` (inklusive Check-ins für das maßgebliche Körpergewicht) und den Erfassungsregeln aus `set-logging` anlegen (D7).
- [ ] 4.2 `InsightAlgorithms` auf `training-volume-v2`/`e1rm-epley-v2` mit effektivem Gewicht (Körpergewicht aus jüngstem Check-in am oder vor dem Trainingstag), Satztypfilter, Wiederholungsrekorden und Rekordverlauf umstellen; `Gainer.UnitTests` lesen die Fixture und sind grün.
- [ ] 4.3 `InsightQueries`, `InsightContracts` und die Coach-Werkzeuge auf die neuen Kennzahlen umstellen; Integrationstest bestätigt, dass gelöschte und laufende Workouts sowie fremde Daten nicht einfließen.

## 5. Verträge und Web

- [ ] 5.1 OpenAPI (`contracts/openapi/Gainer.Api.json`) und `Gainer.Contracts/Sync` regenerieren; CI-Vertragsprüfung grün.
- [ ] 5.2 Trainingsnavigation und -seiten in `apps/web` ausblenden und `generated.ts` aktualisieren; `npm run typecheck`, `npm run lint`, `npm run build` und Playwright-Tests grün.

## 6. Flutter: Domäne, lokale Daten, Sync

- [x] 6.1 `domain/models/training/` auf Workout/Block/Satz/Plan/Übung/Kategorie gemäß D1, D5 und D6 neu aufbauen inklusive Satztyp, Superset-Gruppierung, Satzbeschriftung (W/1/D/2) und Erfassungsregel je Übungstyp; Dart-Unit-Tests für die zugehörigen Spec-Szenarien grün.
- [ ] 6.2 Einmalige lokale Bereinigung bei erhöhter Trainings-Schemaversion (D11) implementieren; Persistenztest: alte Trainings-Envelopes, Outbox-Einträge und Konflikte werden in einer Transaktion entfernt, andere Fachbereiche bleiben unberührt.
- [ ] 6.3 `sync_payload_codec.dart` auf die neuen Operationen umstellen; Codec-Tests gegen Backend-Fixtures grün.
- [ ] 6.4 Coalescing nicht gesendeter `saveWorkout`-Einträge in `LocalSyncStore.commitMutation` implementieren (D3); Persistenztests: 50 Feldänderungen ergeben eine ausstehende Mutation, bereits gesendete Einträge bleiben unverändert, Prozessende nach Bestätigung verliert keinen Wert.
- [ ] 6.5 `TrainingRepository` neu aufbauen: leeres Training, Planstart, Wiederholen, Speichern, Beenden, Löschen, Training als Plan speichern, Merge, Pläne, Rotation, Übungen und Kategorien; Repository-Tests mit Offline-Szenarien und Kontowechsel A/B grün.

## 7. Flutter: Vorwerte und Statistik

- [x] 7.1 Vorwertermittlung mit Quellen „nach Übung“, „nach Plan“, „nach Training“ und Fallback implementieren (D7); Unit-Tests für alle Szenarien der Requirement „Vorwertquelle“ grün.
- [ ] 7.2 Dart-Kennzahlen inklusive Körpergewicht aus lokal vorhandenen Check-ins gegen `contracts/fixtures/training-statistics.json` implementieren; Flutter-Unit-Tests lesen die Fixture und sind grün.

## 8. Flutter: Designsystem

- [x] 8.1 Token-Modell (Farbrollen Hell/Dunkel, Rundungen, Abstände, Typografie) gemäß D12 implementieren und `GainerTheme` ersetzen; automatisierter Kontrasttest prüft alle Rollenpaare beider Modi gegen die Werte der Spec `mobile-design-system`.
- [x] 8.2 Komponentenbibliothek aus D13 umsetzen (Scaffold mit großem Titel, Karten/gruppierte Sektionen, Toolbar- und Pillen-Buttons, Action-Sheet, gestapelter Dialog, Suchfeld, Segment-Control, Ziffernblock-Zubehörleiste); Golden-Tests je Komponente in Hell und Dunkel sowie mit großer Schrift grün.
- [x] 8.3 Schwebende Tableiste mit hervorgehobenem aktiven Tab und Platz für die kompakte Trainingsleiste in `MobileShell` umsetzen; Widget-Test für Tabwechsel und Golden-Test beider Modi.
- [x] 8.4 Prüfung ergänzen, die fest codierte Farben außerhalb von `ui/core/theme/` verbietet; Analyse schlägt bei Verstoß fehl.

## 9. Flutter: Tagebuch und aktives Training

- [ ] 9.1 Training-Tab mit Segment „Tagebuch | Pläne | Statistik“ und Tagebuch nach Monaten mit Datums-Badges und Wischen zum Löschen (D10, Spec `training-screens`) umsetzen; Widget-Test für die Monatsgruppierung und Golden-Test beider Modi.
- [ ] 9.2 Aktives Training als Vollbild-Modal mit Minimieren und kompakter Leiste über der Tableiste in allen Tabs umsetzen; Widget-Tests für Minimieren/Wiederöffnen und Wiederherstellung nach Neustart.
- [ ] 9.3 Übungskarten mit Fußzeilenaktionen und Satzzeilen nach `training-screens` mit Inline-Eingabe (Komma/Punkt, Ziffernblock mit Zubehörleiste zurück/weiter/fertig, Feldfehler), blassen Platzhaltern, Übernahme per Tipp auf die Satznummer, Satztyp-Menü, Duplizieren/Entfernen/Umordnen sowie optionaler RIR-Spalte umsetzen; Widget-Tests decken die Szenarien aus `set-logging` ab.
- [ ] 9.4 Übungsauswahl mit Suche, Kategorien, zuletzt verwendet und Mehrfachauswahl als Superset sowie Neuordnen-Sheet mit Ziehgriffen und Übung ersetzen umsetzen; Widget-Tests für Suche „kniebeu“, Superset-Hinzufügen und Reihenfolge.
- [ ] 9.5 Trainingskopf mit Titel, Notiz und Start/Ende (ohne Körpergewicht) sowie Gewichtseinheit kg/lbs umsetzen; Tests für ungültige Endzeit und lbs-Umrechnung.
- [ ] 9.6 Fehlwerte-Dialog beim Beenden und Trainingszusammenfassung mit Rekordhervorhebung umsetzen; Widget-Tests für „Vorwerte übernehmen“, „Trotzdem beenden“, „Weitertrainieren“ und das 20 kg × 6-Beispiel.
- [ ] 9.7 Bearbeiten und Löschen historischer Trainings sowie „Training wiederholen“ mit Wahl der Vorwertquelle umsetzen; Widget- und Repository-Tests inklusive Offline-Löschen.

## 10. Flutter: Pläne, Übungen, Statistik

- [ ] 10.1 Planliste mit Rotation und Vorschlag „Nächstes Training“, Planeditor (Aufwärm-/Arbeitssätze, Notiz, Superset, Vorwertquelle) und Planstart umsetzen; Widget-Tests für Standardwerte 0/3, Eintrag ohne Sätze und Planstart W, W, 1, 2, 3.
- [ ] 10.2 „Als Plan speichern“ mit Rückfrage bei gleichnamigem Plan umsetzen; Test für Überschreiben und Neuanlage.
- [ ] 10.3 Übungsverwaltung (eigene Übungen, Typ, Kategorien, Faktoren, Archivieren, Typwechsel-Warnung, Zusammenführen) umsetzen; Widget-Tests für die Szenarien aus `exercise-catalog`.
- [ ] 10.4 Statistikbereich mit Übungsliste, Rekorden, Wiederholungsrekorden und Verlauf (1RM, Max. Gewicht, Volumen) sowie Übungsverlauf aus dem Block umsetzen; Widget-Test für Offline-Berechnung.

## 11. Pausentimer und Live Activity

- [x] 11.1 Lokalen Timerzustand mit Generation und kontogebundenen Shortcuts umsetzen (D8); Unit-Tests für manuellen Start, ±15 s, Stop/Start, X setzt auf Ausgangsdauer, Ablauf auf 0:00 bis zum nächsten erfassten Satz und Wiederherstellung nach Prozessende.
- [ ] 11.2 Große Timeransicht und kompakte Leiste über der Tastatur umsetzen, Ton und Haptik bei Ablauf im Vordergrund, lokale Benachrichtigung im Hintergrund; Widget-Test, dass Eingabefokus und Werte beim Öffnen/Schließen erhalten bleiben.
- [ ] 11.3 Live Activity auf „eine Activity pro Training“ umstellen (D9) inklusive Detailfreigabe, Ende bei Beenden/Löschen/Logout/Kontowechsel und Bereinigung veralteter Activities; Swift- und Pigeon-Tests sowie Coordinator-Tests grün.
- [ ] 11.4 Auf einem physischen iPhone mit Dynamic Island und einem ohne (oder Simulator) Bildschirmaufnahmen von App → Home → Sperrbildschirm für die Zustände „ohne Pause“, „Pause läuft“, „pausiert“, „abgelaufen“ und „beendet“ erstellen; Ergebnis im Change-Ordner dokumentieren.

## 12. Bestehende Bereiche im neuen Design

- [x] 12.1 „Heute“/Fortschritt (`progress_screen`, `exercise_progress_section`) auf Komponenten und Farbrollen umstellen; bestehende Widget-Tests unverändert grün, Golden-Tests Hell/Dunkel.
- [x] 12.2 Check-in und Apple-Health-Review (`body_screen`, `health_review_screen_cupertino`) umstellen; bestehende Widget-Tests unverändert grün, Golden-Tests Hell/Dunkel.
- [x] 12.3 Ernährung (`nutrition_screen_cupertino`) umstellen; bestehende Widget-Tests unverändert grün, Golden-Tests Hell/Dunkel.
- [x] 12.4 Coach, Mehr-Menü, Sync & Gerätewechsel, Anmeldung und Kontoverwaltung umstellen; bestehende Widget-Tests unverändert grün, Golden-Tests Hell/Dunkel.
- [ ] 12.5 Home-Screen-Widget der Widget-Extension auf die Farbrollen umstellen; Xcode-Build und Widget-Vorschau in beiden Modi geprüft.

## 13. Integrationsabnahme

- [ ] 13.1 End-to-End auf einem physischen iPhone: Offline ein Training aus einem Plan starten, Sätze eintragen, App beenden, neu öffnen, beenden mit Fehlwerte-Dialog, online gehen und prüfen, dass das Backend genau ein Workout mit identischen Werten und Kennzahlen liefert.
- [ ] 13.2 Kontoisolation End-to-End mit zwei Konten auf demselben Gerät prüfen: Nach Kontowechsel sind weder Trainings, Vorwerte, Timer-Shortcuts noch Live Activity des vorherigen Kontos sichtbar.
- [ ] 13.3 Auf einem physischen iPhone alle Hauptbereiche in Hell und Dunkel sowie mit größter Textgröße und VoiceOver durchgehen; Screenshots je Bereich im Change-Ordner ablegen.
- [ ] 13.4 `pwsh ./scripts/verify.ps1`, Flutter-Analyse und -Tests sowie Mobile-CI vollständig grün; `graphify update .` ausgeführt.

## Workflow follow-up

- Change nach Review mit `/openspec-archive-change` archivieren und die erzeugten Hauptspecs prüfen.
