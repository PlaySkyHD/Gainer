# Proposal

## Why

Der typische Ablauf ist Krafttraining, danach Cardio. Heute muss der Nutzer nach dem Krafttraining erst zurück ins Tagebuch und Cardio einzeln starten. Intervalltraining (z. B. 4×4) ist mit einem festen Zielbereich nicht abbildbar. Und auf dem Ergometer hilft eine Ansage über Kopfhörer mehr als eine Benachrichtigung.

## What Changes

5. **Cardio anhängen:** Nach dem Beenden eines Krafttrainings bietet die Zusammenfassung „Cardio anhängen“ an. Ein Tipp startet mit gemerktem Gurt, letztem Zielbereich bzw. zuletzt genutzter Vorlage. Einstellbar (Standard an).
6. **Intervall-Vorlagen:** Vorlagen aus Phasen (Dauer, Zielbereich als Zone 1–5 oder bpm, Name). Mitgeliefert werden „Zone 2 – 30 min“ und „4×4 (Norwegisch)“, eigene lassen sich anlegen. Während der Einheit wechselt der Zielbereich automatisch. Phasenwechsel werden angekündigt, auch bei gesperrtem Display. Live-Ansicht und Live Activity zeigen Phase und Restzeit.
7. **Sprachansagen:** optional (Standard aus). Sie sagen Alarme, Phasenwechsel und auf Wunsch alle N Minuten Puls und Dauer an. Andere Audiowiedergabe wird dabei leiser gestellt (z. B. Musik).

### Non-Goals

- Kein Teilen oder Synchronisieren von Vorlagen zwischen Nutzern.
- Keine Steuerung des Ergometer-Widerstands.
- Keine eigene Stimme oder Lautstärkeregelung außerhalb von iOS.

## Capabilities

- **Neu:** `cardio-session-flow`.

## Impact

- **Backend:** `CardioSession` erhält optional `Phases` (jsonb: Startversatz, Dauer, Name, Zielbereich) und `TemplateName?`. Dazu Migration und Validierung. Vorlagen selbst bleiben lokal pro Konto in den Cardio-Einstellungen.
- **Pigeon/iOS:**
  - `PlatformCardioMonitoringConfig` erhält `phases` und Sprachoptionen.
  - Swift wechselt die Zone je Phase, meldet Phasenwechsel (Benachrichtigung, Ton, Sprache) und zeigt sie in der Live Activity.
  - `AVSpeechSynthesizer` mit `.duckOthers`.
  - `UIBackgroundModes` erhält `audio`, damit Ansagen bei gesperrtem Display hörbar sind.
- **Flutter:**
  - Vorlagenmodell und Editor, Vorlagenwahl im Start-Sheet.
  - Phasenanzeige in Live und Detail (Zielband als Stufen in der Kurve).
  - „Cardio anhängen“ in der Workout-Zusammenfassung, Einstellungen.
- **Security:** keine neuen Daten außer Phasen. Sprachausgabe nur lokal.
- **Breaking Changes:** keine. Ohne Phasen verhält sich alles wie bisher.
- **Risiko:** Der Hintergrundmodus `audio` muss im App-Review mit hörbaren Ansagen begründbar sein. Er wird nur aktiv genutzt, wenn Sprachansagen eingeschaltet sind.
