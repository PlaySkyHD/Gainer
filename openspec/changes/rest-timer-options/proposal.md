# Proposal

## Why

Die große Timeransicht ist umständlich: Shortcuts müssen erst gewählt und dann gestartet werden, das Verwalten der Shortcuts geschieht inline, und der Ablaufton ist fest der iOS-Standardton. Viele Nutzer möchten außerdem, dass die Pause nach einem erfassten Satz von selbst beginnt.

## What Changes

- Unter dem Ring steht die Zeile „Timer“ mit einem „…“-Button. Er öffnet ein Menü mit „Timersound“, „Timer bearbeiten“ und dem Schalter „Timer automatisch starten“.
- **Shortcuts starten sofort:** Ein Tipp auf einen Shortcut startet den Timer mit dieser Dauer. Nur während der Timer läuft, ist die Shortcut-Zeile ausgeblendet; pausiert ist sie sichtbar. Der „+“-Button der Zeile legt einen neuen Shortcut an.
- **Timer bearbeiten:** Sheet mit großem Titel und den Shortcuts als Liste: rotes Minus zum Löschen, Ziehgriffe zum Sortieren, „+“ öffnet die Minuten/Sekunden-Auswahl, ✓ schließt.
- **Timersound:** Sheet mit Liste der Töne und Häkchen; Antippen spielt den Ton zur Probe und wählt ihn. Der Ton gilt für den Ablauf in der App und für die Benachrichtigung „Pause vorbei“.
- **Timer automatisch starten** (Standard aus): Sobald ein Satz im aktiven Training vollständig erfasst ist, startet der Timer mit der zuletzt gewählten Dauer, sofern kein Timer läuft oder pausiert ist.

### Non-Goals

- Keine kostenpflichtigen oder gesperrten Töne, keine Hilfe-Seite.
- Keine Pausendauer je Übung.

## Capabilities

- **Neu:** `rest-timer-options`.

## Impact

- Flutter: `rest_timer_sheet.dart`, `rest_timer_controller.dart`, `training_preferences.dart`, `workout_view_model.dart`.
- iOS: gebündelte Tondateien, Pigeon-Methode zum Abspielen, Benachrichtigungston nach Auswahl.
