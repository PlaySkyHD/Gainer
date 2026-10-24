# Proposal

## Why

Das bestehende Trainingssystem der iPhone-App ist im Alltag zu umständlich: Workouts lassen sich nur aus Vorlagen starten, jeder Satz braucht einen eigenen Abschluss-Klick, der Pausentimer startet ungefragt, Vorwerte sind beim Eintragen nicht sichtbar und abgeschlossene Trainings sind dauerhaft gesperrt. Das Training wird deshalb als vollständige, schnell bedienbare Logging-Erfahrung nach dem Vorbild etablierter Trainings-Tracker neu aufgebaut. Da noch keine schützenswerten Trainingsdaten existieren, ist jetzt der günstigste Zeitpunkt für einen sauberen Modellwechsel.

## What Changes

- **Trainingsablauf neu:** Training leer starten, aus einem Plan starten oder ein früheres Training wiederholen. Eine aktive Session kann minimiert, beendet oder gelöscht, aber nicht pausiert werden; die Trainingszeit läuft ab Sessionstart.
- **Satzerfassung inline:** Gewicht und Wiederholungen werden direkt in Satzzeilen eingetragen. Ein Satz gilt als erfasst, sobald seine Pflichtwerte gesetzt sind; es gibt keinen separaten Abschluss-Klick. **BREAKING:** `isCompleted`/`completedAtUtc` je Satz entfallen.
- **Vorwerte als Platzhalter:** Leere Felder zeigen blasse Vorwerte aus einer wählbaren Quelle (nach Übung, nach Plan, nach wiederholtem Training). Beim Beenden mit fehlenden Werten fragt ein Dialog: Vorwerte übernehmen, trotzdem beenden oder weitertrainieren.
- **Satztypen und Supersets:** Normal-, Aufwärm- und Dropsätze; Supersets als benachbarte Übungsblöcke mit gemeinsamer Superset-ID; Sätze kopieren; Übungen per Drag & Drop neu ordnen.
- **Trainingsmetadaten:** Titel, Trainingsnotiz, Notiz je Übungsblock und je Satz, Start-/Endzeit. Das Training speichert kein eigenes Körpergewicht; Kennzahlen verwenden das Gewicht aus den täglichen Check-ins.
- **Historie bearbeitbar und löschbar:** Abgeschlossene Trainings bleiben im Tagebuch editierbar und können gelöscht werden. **BREAKING:** Die bisherige Unveränderlichkeit abgeschlossener Workouts (Historienschutz) entfällt. Änderungen an Plänen oder Übungsstammdaten wirken weiterhin nicht rückwirkend auf Trainings.
- **Pläne vereinfacht:** Ein Planeintrag besteht aus Übung, Anzahl Aufwärmsätze, Anzahl Arbeitssätze, Notiz und optionaler Superset-ID. Ein Training kann als Plan gespeichert werden. Die Plan-Rotation bleibt als Vorschlag „Nächstes Training“ erhalten. **BREAKING:** Wiederholungsbereich (min/max) und Pausenzeit je Eintrag entfallen.
- **Pausentimer manuell:** Der Timer startet nur auf Nutzeraktion, besitzt frei wählbare Dauer, ±15-Sekunden-Schritte und eigene Shortcuts. Stop/Start pausiert und setzt fort, Schließen setzt auf die ursprüngliche Dauer zurück; Ablauf erzeugt einen kurzen Ton. **BREAKING:** Automatischer Timerstart nach Satzabschluss sowie `+30 s`/`Überspringen` entfallen.
- **Übungskatalog erweitert:** Übungstyp (zunächst Kraft-Typen), Kategorien, Körpergewichts- und Zusatzgewichtsfaktor, eigene Notiz, Zusammenführen doppelter Übungen.
- **Auswertung:** Trainingszusammenfassung nach Abschluss, Übungsverlauf, persönliche Rekorde und Kennzahlen (Volumen, geschätztes 1RM, Satz-/Wiederholungszahlen) inklusive Körpergewichtsanteil aus dem jüngsten Check-in am oder vor dem Trainingstag.
- **RIR optional:** RIR bleibt als ausblendbares Zusatzfeld je Satz (Standard: aus); Ziel-RIR je Planeintrag entfällt.
- **Gewichtseinheit:** Anzeige und Eingabe in kg oder lbs nach Nutzerpräferenz; gespeichert wird weiterhin kanonisch in kg.
- **Neues App-Design:** Die gesamte iPhone-App erhält ein neues visuelles System mit Hell- und Dunkelmodus nach Systemeinstellung: schwarzer bzw. heller Hintergrund, gerundete gruppierte Karten, Türkis als Akzent, schwebende Tableiste, pillenförmige Toolbar-Aktionen, Bottom-Sheets für Kontextmenüs und gestapelte Dialoge. Trainings-Screens folgen einem festgelegten Layout (Satzzeilen, Übungskarten, Timeransichten, Zusammenfassung). **BREAKING (visuell):** Das bisherige blaue Gainer-Theme entfällt.
- **Daten-Neustart:** Bestehende Trainingsdaten (Workouts, Vorlagen, Rotation, eigene Übungen) werden nicht migriert; Tabellen und lokale Trainingsaggregate werden neu aufgebaut.

### Phasenzuordnung

- **Private Kernjourney (diese Change):** Trainingsablauf, Satzerfassung, Vorwerte, Pläne mit Rotation, Kraft-Übungskatalog, manueller Pausentimer inklusive Live Activity, Zusammenfassung, Übungsverlauf, Rekorde und Kennzahlen.
- **Spätere Phase:** Cardio- und Dauer-/Distanz-Übungstypen, Diagramme über längere Zeiträume, Teilen/Export von Trainings, Apple-Health-Workout-Export.

### Non-Goals

- Keine Web-/PWA-Umsetzung des neuen Trainingssystems; das Web-Frontend wird für Training nicht angepasst.
- Keine Migration bestehender Trainingsdaten.
- Kein paralleles Bearbeiten desselben Kontos auf mehreren Geräten; es gilt weiter das Modell eines aktiven Schreibclients.
- Keine Premium-, Paywall- oder Kauflogik, keine sozialen oder Teilen-Funktionen.
- Kein automatischer Pausentimerstart und keine automatische Pausendauer je Übung.
- Keine Bilder oder Videos im Übungskatalog.
- Keine Neugestaltung der Web-PWA und keine fachlichen Änderungen an Check-in, Ernährung, Coach oder Sync durch das neue Design.

## Capabilities

### New Capabilities

- `training-session`: Lebenszyklus eines Trainings – Start (leer, aus Plan, Wiederholung), aktive Session mit Minimieren, Beenden inklusive Fehlwerte-Dialog, Löschen, Bearbeiten historischer Trainings, Trainingsmetadaten und Zusammenfassung.
- `set-logging`: Übungsblöcke und Sätze innerhalb eines Trainings – Inline-Eingabe, Erfassungsregel ohne Abschluss-Flag, Satztypen, Nummerierung, Supersets, Kopieren, Umordnen, optionales RIR, Gewichtseinheit und Vorwerte mit Quellenstrategie.
- `training-plans`: Trainingspläne mit Einträgen aus Übung, Aufwärm-/Arbeitssätzen, Notiz und Superset, Planstart, „Training als Plan speichern“ sowie Rotation mit Vorschlag des nächsten Plans.
- `exercise-catalog`: Basis- und eigene Übungen mit Übungstyp, Kategorien, Faktoren, Suche, Archivierung und Zusammenführen.
- `rest-timer`: Manueller Pausentimer mit Shortcuts, Pausieren/Fortsetzen, Zurücksetzen, Ablaufsignal sowie Darstellung von Trainingszeit und Pause in Live Activity und Dynamic Island.
- `training-statistics`: Deterministische Trainingskennzahlen, Übungsverlauf, geschätztes 1RM und persönliche Rekorde inklusive Körpergewichtsanteil.
- `mobile-design-system`: App-weites visuelles System der iPhone-App – Hell-/Dunkelmodus, Farbrollen, Kontrast, Karten und Rundungen, Typografie, schwebende Tableiste, Toolbar-Aktionen, Sheets und Dialoge sowie Umstellung aller bestehenden Bereiche.
- `training-screens`: Aufbau und Bedienung der Trainings-Screens – Tagebuch, Trainingskopf, Metadaten- und Übungskarten, Satzzeilen, Zahleneingabe, Timeransichten, Übungsauswahl, Fehlwerte-Dialog, Zusammenfassung, Plan- und Wiederholen-Ansichten sowie Live-Activity-Layout.

### Modified Capabilities

Keine. `openspec/specs/` enthält noch keine archivierten Capabilities. Die neuen Capabilities ersetzen inhaltlich die noch nicht archivierten Anforderungen `workout-execution` und `exercise-and-plan-management` aus `build-ai-body-training-tracker-mvp` sowie die Timer-Teile von `apple-native-training` aus `migrate-pwa-to-ios-first-flutter`. Diese Planungsartefakte werden im Rahmen der Umsetzung als abgelöst gekennzeichnet, damit beim Archivieren keine widersprüchlichen Anforderungen entstehen.

## Impact

- **Backend-Domäne (`src/Gainer.Core/Training`):** `Workout`, `WorkoutExercise`, `WorkoutSet`, `Exercise`, `WorkoutTemplate(Item)` und Mutationen (`StartWorkoutMutation`, `EditWorkoutMutation`, `CompleteWorkoutMutation`, `DiscardWorkoutMutation`) werden umgebaut; neu sind Satztyp, Superset-ID, Titel, Notizen, Endzeit-Bearbeitung, Löschen, Übungstyp, Kategorien, Faktoren und Merge. `PreviousPerformance` erhält Quellenstrategien.
- **Persistenz (`src/Gainer.Infrastructure/Persistence`):** Neue EF-Core-Migration, die Trainingstabellen neu aufbaut; `WorkoutHistoryProtectionInterceptor` entfällt; `WorkoutMutationHandler`, `WorkoutTemplateMutationHandler`, `WorkoutRotationHandler`, `PreviousPerformanceQueries`, `WorkoutHistoryQueries`, `InsightQueries` und `SyncMutationExecutor` werden angepasst. Seed-Basiskatalog erhält Typen, Kategorien und Faktoren.
- **API und Verträge:** Sync-Mutationstypen für Workouts, Pläne, Übungen und Kategorien in `Gainer.Contracts/Sync` und `contracts/openapi/Gainer.Api.json`; `ExerciseCatalogController`/`ExerciseCatalogResponse` und `InsightContracts` werden erweitert. Die API-Version bleibt `/api/v1`; inkompatible Payloads werden über eine neue Payload-Schemaversion abgegrenzt.
- **Flutter-App (`apps/mobile`):** Neuaufbau von `ui/features/training/*`, `domain/models/training/training.dart`, `data/repositories/training/*` und der Workout-Teile von `sync_payload_codec.dart`; neue Tagebuch-, Plan-, Statistik-, Aktiv-Trainings-, Timer- und Zusammenfassungsansichten; Anpassung von `NativeLiveActivities.swift` und `best_effort_rest_timer_notification_port.dart`. Für das Designsystem: neues `ui/core/theme.dart` mit Farbrollen für Hell/Dunkel, gemeinsame Komponenten unter `ui/core/components/`, schwebende Tableiste in `ui/core/shell/mobile_shell.dart` und Umstellung aller bestehenden Feature-Screens (`progress`, `body`, `nutrition`, `coach`, `sync`, `access`, `body/health`) sowie der Widget-Extension.
- **Lokale Daten:** Lokale Trainingsaggregate und zugehörige Outbox-Einträge werden beim Update einmalig verworfen.
- **Sicherheit:** Alle neuen Entitäten (Kategorien, Pläne, Workouts, Sätze) tragen die UserId und werden ausschließlich über die authentifizierte Sitzung zugeordnet. Merge, Wiederholen und Planstart dürfen nur eigene oder Basis-Übungen referenzieren; fremde IDs werden ohne Datenoffenlegung abgelehnt. Live Activity zeigt Übungsdetails nur nach ausdrücklicher Freigabe. Das Löschen von Trainings ist ein Soft-Delete mit Tombstone für den Sync.
- **Web-PWA (`apps/web`):** Keine Anpassung; die bisherigen Trainingsseiten sind nach dem Backend-Umbau nicht mehr kompatibel und werden ausgeblendet.
