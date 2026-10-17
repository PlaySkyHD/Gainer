# Design

## Context

Motivation und Umfang: siehe `proposal.md`. Verhalten: siehe die sechs Specs unter `specs/`.

Ist-Zustand, der den Ansatz bestimmt:

- **Backend:** `Gainer.Core/Training` modelliert `Workout` → `WorkoutExercise` → `WorkoutSet` als relationale Tabellen mit `UserId` (über `UserOwnedEntity`). Mutationen laufen ausschließlich über den Sync-Vertrag (`SyncMutationsController` → `SyncMutationProcessor` → `SyncMutationExecutor` → `*MutationHandler`) mit Versionserwartung je Ressource (`ResourceKey`, `AtomicMutationScope`). `EditWorkoutMutation` überträgt bereits den vollständigen Übungs-/Satz-Snapshot eines Workouts. `WorkoutHistoryProtectionInterceptor` blockiert jede Änderung nicht laufender Workouts.
- **Flutter:** Trainingsdaten liegen als JSON-Envelopes in `LocalResources` (Typ `workout`, `workout-template`, `workout-rotation`, `custom-exercise`); jede Änderung wird per `LocalSyncStore.commitMutation` atomar mit einem Outbox-Eintrag geschrieben. `sync_payload_codec.dart` übersetzt lokale Operationen in Backend-Operationen. Native Live Activity und Timer-Benachrichtigung existieren (`NativeLiveActivities.swift`, `best_effort_rest_timer_notification_port.dart`).
- **Insights:** `InsightAlgorithms` kennt bereits `training-volume-v1` und `e1rm-epley-v1`, ohne Körpergewichtsanteil und Satztypen.
- Es existieren keine schützenswerten Trainingsdaten (Nutzerentscheidung).

## Goals / Non-Goals

**Goals:**

- Das Workout bleibt **ein Aggregat** mit vollständigem Snapshot pro Mutation; dadurch bleibt der bestehende idempotente Sync-Vertrag inklusive Versionsprüfung nutzbar.
- Satzeingaben fühlen sich sofort an: lokale Speicherung je Feldänderung, ohne die Outbox mit hunderten Mutationen pro Training zu fluten.
- Kennzahlen werden in genau einer Formelversion definiert und in C# und Dart identisch implementiert und gegen gemeinsame Testfälle geprüft.

**Non-Goals:**

- Kein Feld-für-Feld-Delta-Sync und kein CRDT; es bleibt bei einem aktiven Schreibclient pro Konto.
- Keine neuen Prozesse oder Services; alles bleibt im modularen Monolithen.
- Keine Anpassung der Web-PWA außer dem Ausblenden der Trainingsseiten.

## Decisions

### D1 – Neues Workout-Datenmodell statt Erweiterung des Status-Modells

`Workout` erhält `Title`, `Notes`, `StartedAtUtc`, `EndedAtUtc?`, `PreviousValueSource` (`exercise`/`plan`/`workout`), `SourcePlanId?`, `SourceWorkoutId?`, `DeletedAtUtc?`, `Version`. Der Status ergibt sich aus `EndedAtUtc` (aktiv = null) und `DeletedAtUtc`. `WorkoutStatus` (`Running`/`Completed`/`Discarded`) entfällt.
`WorkoutExercise` (Block): `SourceExerciseId`, `ExerciseNameSnapshot`, `ExerciseTypeSnapshot`, `Position`, `Notes`, `SupersetId?`.
`WorkoutSet`: `Position`, `SetType` (`normal`/`warmup`/`dropset`), `WeightKg?`, `Repetitions?`, `Rir?`, `Notes?`. `IsCompleted`/`CompletedAtUtc` entfallen; „erfasst“ ist eine abgeleitete Regel (Spec `set-logging`).

*Alternative:* Status-Enum behalten und `Completed` editierbar machen. Verworfen, weil „aktiv über Mitternacht“, Endzeit-Bearbeitung und Wiederöffnen sich mit einem Enum doppelt modellieren und auseinanderlaufen würden.

Der Übungstyp wird als Snapshot im Block gespeichert, damit die Erfassungsregel einer historischen Einheit stabil bleibt. Eine spätere Typänderung der Übung wirkt laut Spec bewusst auf Auswertungen; Statistik liest daher den aktuellen Typ, die Satzeingabe den Snapshot.

### D2 – Mutationsschnitt für Workouts

Neue Sync-Operationen ersetzen `startWorkout`/`editWorkout`/`completeWorkout`/`discardWorkout`:

| Operation | Inhalt | Versionserwartung |
|---|---|---|
| `createWorkout` | vollständiger Snapshot (leer, aus Plan oder aus Wiederholung vom Client aufgebaut) | Workout = 0 |
| `saveWorkout` | vollständiger Snapshot inklusive Metadaten und optional `EndedAtUtc` | Workout = Basisversion |
| `finishWorkout` | Snapshot plus Endzeit; schreibt Rotationsfortschritt, wenn der Plan in der Rotation ist | Workout und ggf. Rotation |
| `deleteWorkout` | nur ID | Workout = Basisversion; erzeugt Tombstone |

Der Server baut Pläne **nicht** selbst in Workouts um; der Client erzeugt den Snapshot (offline-fähig). Der Server validiert: Eigentum an Workout/Plan/Quell-Workout, referenzierte Übungen sind Basisübungen oder eigene (auch archivierte, für Historie), Wertebereiche, Endzeit > Startzeit, höchstens ein aktives Workout pro Nutzer (partieller Unique-Index auf `UserId` WHERE `EndedAtUtc IS NULL AND DeletedAtUtc IS NULL`).

*Alternative:* feingranulare Mutationen (`setValue`, `addSet` …). Verworfen: vervielfacht Handler, Codec und Konfliktfälle, ohne dass Mehrgeräte-Bearbeitung ein Ziel ist.

### D3 – Coalescing von Workout-Edits in der Outbox

Inline-Eingabe erzeugt pro gültiger Feldänderung eine lokale Speicherung. Um die Outbox klein zu halten, ersetzt `commitMutation` für Aggregattyp `workout` und Operation `saveWorkout` den **letzten noch nicht gesendeten** `saveWorkout`-Eintrag desselben Workouts (gleiche Sequenzposition, neuer Payload), statt einen weiteren anzuhängen. Bereits gesendete oder in Bearbeitung befindliche Einträge werden nie verändert. Die Ersetzung erfolgt in derselben Transaktion wie das Envelope-Update, damit „lokal gespeichert“ weiterhin atomar bleibt.

*Alternative:* Debounce in der UI (z. B. 800 ms) vor dem lokalen Speichern. Verworfen, weil ein Prozessende in diesem Fenster bestätigte Eingaben verlieren würde (Spec `set-logging`, Szenario „Prozessabbruch nach Eingabe“).

### D4 – Historie bearbeitbar, Stammdaten bleiben entkoppelt

`WorkoutHistoryProtectionInterceptor` wird entfernt. Entkopplung von Plänen und Übungen bleibt über Snapshots (Name, Typ) und dadurch gesichert, dass Plan-/Übungs-Handler niemals Workout-Tabellen schreiben. Einzige Ausnahme ist `mergeExercises`, das `SourceExerciseId` in Blöcken und Planeinträgen des Nutzers umschreibt, `ExerciseNameSnapshot` aber unverändert lässt. Merge ist eine eigene Mutation mit Versionserwartung auf beide Übungen; betroffene Workouts und Pläne erhalten eine neue Version und erscheinen im Change-Feed, damit der Client sie neu lädt.

### D5 – Pläne ersetzen Templates

`WorkoutTemplate`/`WorkoutTemplateItem` werden zu `TrainingPlan`/`TrainingPlanEntry` umgebaut: `Name`, `Notes`, `PreviousValueSource`, `SortOrder`, `IsArchived`; Einträge mit `ExerciseId`, `WarmupSets`, `WorkingSets`, `Notes`, `SupersetId?`. Wiederholungsbereich, Ziel-RIR und Pausenzeit entfallen. `WorkoutRotation` bleibt fachlich erhalten und verweist auf Pläne. Der Rotationsvorschlag wird aus dem jüngsten nicht gelöschten, beendeten Workout mit `SourcePlanId` in der Rotation abgeleitet statt aus einem gespeicherten `LastCompletedTemplateId`, damit Löschen und Bearbeiten automatisch korrekt wirken (Spec `training-plans`, Szenario „Letztes Training gelöscht“).

### D6 – Übungskatalog: Typ, Kategorien, Faktoren

`Exercise` erhält `ExerciseType` (`strength`, `bodyweightLoaded`, `bodyweightOnly`, `assisted`), `Notes`, `BodyweightFactor?` (0–1), `WeightFactor?` (0–10). Neu: `ExerciseCategory` (Basis oder eigen, `OwnerUserId?`) und Zuordnungstabelle `ExerciseCategoryAssignment` (UserId-gebunden für eigene Zuordnungen). Der Seed `ExerciseCatalogSnapshot` wird um Typ, Kategorien und Faktoren erweitert und als neue Katalogversion ausgeliefert. Cardio-/Dauer-Typen werden im Enum nicht angelegt, um keine halben Eingabepfade zu erzeugen; die Erweiterung ist additiv möglich.

### D7 – Vorwerte und Statistik: gleiche Logik in Dart und C#

Vorwerte werden **nur im Client** aus lokalen Daten berechnet (Platzhalter, offline). Kennzahlen werden in Dart (Statistikbereich, Zusammenfassung) und C# (`InsightAlgorithms`, Coach) implementiert. Damit beide nicht auseinanderlaufen, gibt es eine gemeinsame JSON-Fixture-Datei mit Eingabe-Trainings und erwarteten Kennzahlen unter `contracts/fixtures/training-statistics.json`, die von `Gainer.UnitTests` und den Flutter-Unit-Tests gelesen wird. Neue Algorithmusversionen: `training-volume-v2`, `e1rm-epley-v2` (mit effektivem Gewicht und Satztypfilter).

Das Körpergewicht kommt ausschließlich aus `DailyCheckIn` (Pflichtfeld `WeightKg`, Schlüssel `LocalDate`): maßgeblich ist der jüngste eigene Check-in mit `LocalDate` am oder vor dem lokalen Starttag des Trainings. Das Training speichert kein eigenes Körpergewicht, damit es keine doppelte Pflege gibt. Backend-Kennzahlen lesen die Check-ins über die bestehenden Body-Queries; die App nutzt die lokal vorhandenen Check-in-Aggregate, sodass auch die Offline-Statistik korrekt ist.

*Alternative:* Statistik nur im Backend abrufen. Verworfen, weil der Statistikbereich offline funktionieren muss und das Ergebnis direkt nach dem Beenden in der Zusammenfassung gebraucht wird.

`PreviousPerformanceQueries` im Backend entfällt, sofern kein anderer Verbraucher (Coach) ihn benötigt; der Coach nutzt die Kennzahlen-Queries.

### D8 – Timerzustand lokal, nicht synchronisiert

Der Pausentimer ist Gerätezustand: Er wird nicht mehr im Workout-Aggregat (`restTimer`) gespeichert, sondern in `LocalSyncMetadata` unter einem kontogebundenen Schlüssel (`trainingTimer:<workoutId>`) mit `{baseDurationSeconds, targetAtUtc?, pausedRemainingSeconds?, generation}`. Shortcuts liegen kontogebunden im selben Speicher. Damit erzeugen Timeraktionen keine Sync-Mutationen und keine Workout-Versionen. Die Generation verhindert, dass ein verspätetes Live-Activity- oder Benachrichtigungs-Update eine neuere Pause überschreibt.

*Alternative:* Timer im Workout belassen (Ist-Zustand). Verworfen, weil jede ±15 s-Aktion eine Workout-Version erzeugen würde und Timerdaten auf einem anderen Gerät ohnehin wertlos sind.

### D9 – Live Activity: eine Activity pro Training

Die bestehende Bridge (`NativeLiveActivities.swift`, Pigeon `MobilePlatformApi`) wird von „Pause“ auf „Training“ umgestellt: Start beim ersten Öffnen eines aktiven Trainings (sofern erlaubt), Content-State `{startedAt, timerState, timerTargetAt?, pausedRemaining?, expired, detail?}`. Trainingszeit und Countdown werden über `Text(timerInterval:)` systemseitig gerendert, damit keine Hintergrundausführung nötig ist. Ende bei Beenden, Löschen, Logout und Kontowechsel über den vorhandenen `NativeFeatureLifecycleCoordinator`. Details nur mit Freigabe (bestehende Einstellung).

### D10 – Navigation in der App

Der Tab „Training“ bleibt in der vorhandenen Tableiste (`MobileArea.training`) und erhält ein Segment „Tagebuch | Pläne | Statistik“. Das aktive Training öffnet als Vollbild-Modal mit Minimieren; minimiert erscheint eine kompakte Leiste oberhalb der Tableiste in **allen** Tabs (Teil von `MobileShell`). Die Tableiste selbst wird durch eine eigene schwebende, gerundete Leiste ersetzt (D12). Übungsauswahl, Neuordnen, Fehlwerte-Dialog und Zusammenfassung sind Sheets bzw. Dialoge im Cupertino-Stil.

*Alternative:* Eigene Tabs für Tagebuch/Pläne/Statistik. Verworfen, weil die Tableiste mit Heute, Check-in, Essen, Training und Mehr bereits voll ist.

### D12 – Designsystem als eigene Theme-Schicht

`GainerTheme` wird durch ein Token-Modell ersetzt: `GainerColors` (Farbrollen je Modus), `GainerRadii`, `GainerSpacing`, `GainerTypography`, bereitgestellt über ein `InheritedWidget` neben `CupertinoTheme`. Widgets lesen nur Rollen, nie Hex-Werte; ein Lint-/Test-Check sucht nach `Color(0x` außerhalb von `ui/core/theme/`.

Startwerte der Farbrollen (in der Umsetzung per Kontrastmessung zu bestätigen):

| Rolle | Dunkel | Hell |
|---|---|---|
| Hintergrund | `#000000` | `#F2F2F7` |
| Fläche (Karte) | `#1C1C1E` | `#FFFFFF` |
| Erhöhte Fläche (Sheet, Button-Fläche) | `#2C2C2E` | `#E9EFF0` |
| Trenner | `#38383A` | `#D8DEDF` |
| Primärtext | `#FFFFFF` | `#191C1D` |
| Sekundärtext | `#A1A1A6` | `#5F6869` |
| Platzhalter/Vorwert | `#5E5E63` | `#B4BCBD` |
| Akzent | `#54D9E6` | `#00828D` |
| Inhalt auf Akzent | `#00363B` | `#FFFFFF` |
| Timer-Stopp / Warnung | `#FFA400` | `#E9651F` |
| Destruktiv | `#FF453A` | `#DD2C00` |

Rundungen: Karten und Sheets 20 pt, Eingabe-/Suchfelder 14 pt, Buttons Pille, Icon-Buttons Kreis 44 pt. Abstände 4/8/12/16/24 pt. Typografie über Cupertino-Systemschrift mit Dynamic Type; Countdown und Trainingszeit mit `FontFeature.tabularFigures()`.

*Alternative:* Material 3 mit eigener Farbpalette. Verworfen, weil die App konsequent Cupertino nutzt und Material-Komponenten auf iOS fremd wirken.

### D13 – Komponentenbibliothek und Umstellungsreihenfolge

Unter `ui/core/components/` entstehen wiederverwendbare Bausteine: `GainerScaffold` (großer Titel → kompakte Leiste), `GainerCard`/`GainerGroupedSection`, `GainerToolbarButton`/`GainerPillButton`, `GainerActionSheet` (Aktionsreihe + Gruppen), `GainerStackedDialog`, `GainerFloatingTabBar`, `GainerSearchField`, `GainerSegmentedControl`, `GainerNumericAccessoryBar`. Zuerst werden Theme und Komponenten mit Golden-Tests in Hell und Dunkel gebaut, dann die Trainings-Screens darauf aufgesetzt und anschließend die bestehenden Bereiche Bildschirm für Bildschirm umgestellt. Jede Umstellung ist rein visuell; bestehende Widget-Tests der Fachlogik müssen unverändert grün bleiben.

Die Zahleneingabe nutzt die iOS-Ziffernblock-Tastatur mit eigener Zubehörleiste (`GainerNumericAccessoryBar`: zurück, weiter, fertig, Tastatur ausblenden), damit Fokuswechsel zwischen Satzfeldern ohne Antippen möglich ist.

### D14 – Live-Activity-Gestaltung

SwiftUI-Layouts der Widget-Extension übernehmen dieselben Farbrollen (als Asset-Katalog-Farben mit Hell/Dunkel-Varianten). Sperrbildschirm: dunkle Karte, App-Icon + Titel oben links, Trainingszeit oben rechts, mittig Übungsname groß und „Satz x von y“ bzw. großer Countdown. Dynamic Island kompakt: App-Symbol links, Zeit bzw. Countdown rechts; abgelaufen 0:00 in Akzentfarbe.

### D11 – Datenneustart

Eine EF-Core-Migration löscht die Tabellen `Workouts`, `WorkoutExercises`, `WorkoutSets`, `WorkoutTemplates`, `WorkoutTemplateItems`, `WorkoutRotations`, `WorkoutRotationItems` sowie eigene Übungen und legt das neue Schema an. Sync-Idempotenzeinträge und Tombstones für die alten Ressourcentypen werden entfernt. Der Client erhöht seine lokale Trainings-Schemaversion; beim ersten Start nach dem Update verwirft er Trainings-Envelopes, zugehörige Outbox-Einträge und Konflikte in einer Transaktion und lädt den Katalog neu. Alte Clients werden über die vorhandene Mindestversionsprüfung des Sync-Vertrags abgewiesen, statt alte Payloads an den neuen Server zu senden.

## Risks / Trade-offs

- [Vollständige Snapshots werden bei langen Trainings groß, z. B. 10 Übungen × 6 Sätze] → Payload bleibt im niedrigen zweistelligen KB-Bereich; zusätzlich reduziert Coalescing (D3) die Zahl der Uploads. Das Backend setzt Obergrenzen (z. B. 50 Blöcke, 50 Sätze je Block).
- [Dart- und C#-Formeln laufen auseinander] → gemeinsame Fixture-Datei (D7), CI bricht bei Abweichung.
- [Historie editierbar und Statistik-Caches veralten] → Kennzahlen werden bei Abruf aus den Trainings berechnet, nicht persistiert; bei Bedarf später Cache mit Workout-Version als Schlüssel.
- [Merge schreibt Referenzen in vielen Workouts um und erzeugt viele neue Versionen] → Merge ist selten; Change-Feed liefert die betroffenen Workouts paketweise; ein laufender Upload desselben Workouts wird über die Versionserwartung als Konflikt erkannt und über die vorhandene Konfliktwiederherstellung gelöst.
- [Partieller Unique-Index „ein aktives Workout“ kollidiert mit offline gestarteten Trainings nach Gerätewechsel] → Single-Writer-Modell verhindert parallele Clients; Konflikt wird als sichtbarer Sync-Konflikt gemeldet, nicht still verworfen.
- [Live Activity zeigt nach Prozessende veraltete Daten] → `staleDate` auf Ende der Pause bzw. +8 h für Trainings; Bereinigung beim nächsten App-Start.
- [Die App-weite Umgestaltung berührt viele Screens und kann fachliche Regressionen einschleusen] → Umstellung strikt visuell (D13), bestehende Widget-Tests bleiben unverändert, Golden-Tests in Hell/Dunkel je Komponente; Screens einzeln in eigenen Commits.
- [Neue Farbwerte verfehlen Kontrastanforderungen] → automatisierter Kontrasttest über alle Rollenpaare beider Modi.
- [Web-PWA wird für Training unbrauchbar] → bewusst akzeptiert (Non-Goal); die Trainingsnavigation wird im Web ausgeblendet, damit keine kaputten Seiten erreichbar sind.

## Migration Plan

1. Backend-Schema-Migration und neue Sync-Operationen ausliefern; dabei die Mindest-Clientversion des Sync-Vertrags anheben.
2. Gleichzeitig die neue App-Version verteilen; beim ersten Start räumt sie lokale Trainingsdaten auf (D11).
3. Web-Build mit ausgeblendeter Trainingsnavigation ausliefern.
4. Rollback: Da keine Daten migriert werden, ist ein Rollback ein Zurücksetzen von Server und App auf die vorherige Version mit erneutem Leeren der Trainingstabellen; neu erfasste Trainings gehen dabei verloren. Das ist für die private Beta akzeptiert.

## Open Questions

- Sollen Timer-Shortcuts später kontoübergreifend synchronisiert werden? Kann ohne Spec-Änderung additiv über die Nutzereinstellungen ergänzt werden.
- Welche Basis-Kategorien und Körpergewichtsfaktoren erhält der Seed-Katalog im Detail? Wird bei der Katalogpflege festgelegt; das Verhalten ist durch die Specs bestimmt.
