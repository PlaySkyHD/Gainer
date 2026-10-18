# Design

## Decisions

### D1 – Töne

Sieben eigene, kurze Töne (≤ 3 s, 16-bit PCM WAV, 44,1 kHz, mono), synthetisch erzeugt und damit lizenzfrei, liegen als Flutter-Assets unter `apps/mobile/assets/sounds/`: `digital_alarm` (Digitaler Wecker), `boxing_bell` (Boxglocke), `radar` (Radar), `bike_bell` (Fahrradklingel), `gong` (Gong), `chime` (Glockenspiel), `pulse` (Signal). Zusätzlich `system` (iOS-Standard). Standard ist `digital_alarm`. Das Erzeugungsskript liegt unter `apps/mobile/tool/generate_timer_sounds.py`, damit die Dateien reproduzierbar sind.

### D2 – Abspielen und Benachrichtigung

- Swift kopiert die Dateien beim ersten Bedarf aus dem Flutter-Asset-Pfad (`FlutterDartProject.lookupKey(forAsset:)`) nach `Library/Sounds/` des App-Containers. Dort findet `UNNotificationSound(named:)` sie, ohne dass das Xcode-Projekt Ressourcen eintragen muss.

- Pigeon `playTimerSound(String soundId)` spielt den Ton über `AVAudioPlayer` mit der Audio-Session-Kategorie `.ambient` (mischt sich mit Musik, respektiert den Stummschalter nicht zwingend – wie andere Timer-Apps; bei `system` `AudioServicesPlaySystemSound(1005)`).
- `schedulePauseNotification` erhält `soundId`; die Benachrichtigung nutzt `UNNotificationSound(named:)` mit der WAV-Datei bzw. `.default` für `system`.
- `RestTimerAlertPort.playExpiry` spielt den gewählten Ton, wenn die App ohne Benachrichtigungsberechtigung im Vordergrund ist (bisheriges Verhalten, nur anderer Ton).

### D3 – Einstellungen

`TrainingPreferenceValues` erhält `timerSoundId` (Standard `digital_alarm`) und `autoStartRestTimer` (Standard `false`). Beide sind lokal pro Konto wie die übrigen Trainingseinstellungen. Unbekannte gespeicherte Sound-IDs fallen auf den Standard zurück.

### D4 – Automatischer Start

`WorkoutViewModel` erkennt den Übergang eines Satzes von „nicht erfasst“ zu „erfasst“ (Pflichtwerte gesetzt, wie die vorhandene Erfassungsregel) im aktiven Training. Ist `autoStartRestTimer` an und der Timer im Zustand bereit oder abgelaufen, wird er mit der Basisdauer gestartet. Das Bearbeiten bereits erfasster Sätze startet nichts. Aufwärmsätze lösen den Start ebenfalls aus, historische Trainings nie.

### D5 – Oberfläche

- Timer-Sheet: unter ±15 s/Start die Zeile „Timer“ links und „…“ rechts (Kreis-Icon), darunter die Shortcut-Chips mit „+“ vorne – nur im Zustand bereit/abgelaufen.
- „…“ öffnet ein kompaktes Popover-Menü (verankert am Button) mit „Timersound“ (Lautsprecher-Icon), „Timer bearbeiten“ (Stift-Icon) und „Timer automatisch starten“ (Checkbox-Icon, Zustand sichtbar).
- „Timersound“ und „Timer bearbeiten“ sind Sheets über `showGainerSheet` mit großem Titel links und ✓-Button rechts oben.
