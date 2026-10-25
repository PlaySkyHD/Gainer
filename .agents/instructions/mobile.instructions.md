---
description: 'Konventionen für die Flutter-iOS-App, ihren Swift-Code und ihre Tests.'
applyTo: 'apps/mobile/**'
paths:
  - "apps/mobile/**"
---

# Mobile-App

Stack: Flutter nur mit Cupertino-Widgets, `provider`, Drift als lokale Datenbank, Pigeon für Swift (HealthKit, Kamera, Live Activities, Passkeys).

## Aufbau

- `lib/domain/models` enthält reine Modelle und Regeln. `lib/data/repositories` und `lib/data/services` enthalten lokale Speicherung, Sync und native Dienste. `lib/ui/features/<bereich>` enthält Screens und ViewModels.
- ViewModels erweitern `ChangeNotifier`; Screens hören mit `ListenableBuilder` zu.
- Fachliche Änderungen laufen über `LocalSyncStore.commitMutation`, damit lokaler Stand und Outbox-Eintrag atomar gespeichert werden. Nie direkt in Tabellen schreiben.

## Oberfläche

- Bausteine aus `lib/ui/core/components` verwenden (`GainerGroupedSection`, `GainerListRow`, `showGainerSheet` …), bevor eigene entstehen. Maßstab ist der Trainings-Tab.
- Texte auf Deutsch, Zahlen deutsch formatiert und immer beschriftet.
- Bei Textgröße 2 und knapp unter der Stapel-Schwelle darf nichts überlaufen; ab der Schwelle Beschriftung über die Eingabe stapeln. Wie Überlauf-Tests scrollen und welche Textgrößen sie prüfen, steht in `docs/agent-lessons-learned.md` im Abschnitt „Tests und visuelle Kontrolle“.
- Von außen geöffnete Vollbilder über `pushSingleInstance`.
- Nichts anbieten, was im aktuellen Zustand nicht funktionieren kann.
- Die Animations-Skills (`animate`, `review-animations`, `emil-design-eng` …) zeigen CSS und Framer Motion. In Flutter: `Curves.easeOut` statt `ease-out`, implizite Animationen (`AnimatedContainer`, `AnimatedOpacity`) statt CSS-Transitions, `SpringSimulation` für Federn, `MediaQuery.disableAnimationsOf(context)` statt `prefers-reduced-motion`.

## Prüfen

- In einem frischen Worktree zuerst `flutter pub get`. Ohne läuft der Analyzer mit einer langen Warnliste voll.
- `flutter analyze`, `flutter test --reporter failures-only <ordner>`, `dart format --set-exit-if-changed lib test pigeons`.
- Lokal nur die betroffenen Ordner testen. Die gesamte Suite dauert 13–19 Minuten, die CI prüft sie.
  - Betroffen sind die Ordner aller Nutzer eines geänderten Bausteins, nicht nur seiner eigenen Tests. Die Nutzer listet `grep -rl <Baustein> lib test`.
  - Änderungen in `lib/ui/core/` wirken auf alle Screens: `test/ui`, `test/mobile_shell_test.dart` und `test/data/services/mobile_auth_controller_test.dart` testen. Das dauert länger als 10 Minuten, also mit `run_in_background` starten.
- Ausgaben nicht ungefiltert zurückgeben: Sie bleiben für alle folgenden Turns im Kontext.
- Lesbare Golden-Vorschau: `tool/preview_goldens.sh test/ui/<bereich>`, danach `rm -rf test/zz_preview`.
- Nach Änderungen an `pigeons/mobile_platform_api.dart` neu generieren und die generierte Datei formatieren.
- Swift kompiliert nur in der CI: Änderungen zeilenweise prüfen, neue Dateien in `Runner.xcodeproj/project.pbxproj` eintragen.
