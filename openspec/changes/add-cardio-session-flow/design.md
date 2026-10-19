# Design

## Decisions

### D1 – Cardio anhängen

- **Zusammenfassung:** `workout_summary_screen` zeigt nach dem Beenden eines Krafttrainings unter den Kennzahlen eine Karte „Cardio anhängen“, mit Vorlage bzw. Zielbereich und Gurtstatus.
  - „Starten“ ruft `CardioSessionController.start` mit den letzten Werten auf und öffnet die Live-Ansicht.
  - „Anpassen“ öffnet das Start-Sheet.
- **Nicht angezeigt** bei laufender Cardio-Einheit, bei historischen Trainings oder wenn `CardioPreferences.offerAfterStrength` aus ist.
- **Verknüpfung:** keine fachliche Verbindung zwischen Workout und Cardio-Einheit. Beide stehen getrennt im Tagebuch.

### D2 – Vorlagen und Phasen

- **Modell:** `CardioTemplate { id, name, phases: [ { name, durationSeconds 30–3600, target: zone(1–5) | bpm(low, high) | none } ] }`, höchstens 30 Phasen und 4 h gesamt.
  - Gespeichert lokal in den Cardio-Einstellungen (`templates`, `lastTemplateId`).
- **Mitgeliefert:**
  - „Zone 2 – 30 min“: 1 Phase, Zone 2.
  - „4×4 (Norwegisch)“: Aufwärmen 10 min Zone 2, viermal 4 min Zone 4 mit 3 min Zone 2 dazwischen, Ausfahren 5 min Zone 1.
- **Auflösung beim Start:** Zonen werden in bpm übersetzt (`CardioZones`). Ohne Zoneneinstellung lassen sich Vorlagen mit Zonenzielen nicht starten; die App erklärt den Grund und verweist auf die Einstellungen.
- **Freie Einheit:** Ohne Vorlage entsteht eine Einheit mit einer offenen Phase (bisheriges Verhalten).
- **Gespeichert:** Die Einheit enthält `templateName` und die aufgelösten `phases` mit `startOffsetSeconds`, `durationSeconds`, `name`, `lowBpm?` und `highBpm?`. `targetZone` ist die Zone der längsten Phase, so bleiben Tagebuch und Statistik kompatibel.
- **Backend-Validierung:** höchstens 30 Phasen, Versatz aufsteigend und ohne Überlappung, Zonengrenzen wie bisher.
- **Zeit im Zielbereich:** wird gegen die jeweils gültige Phase gerechnet.

### D3 – Native Phasen

- **Konfiguration:** `PlatformCardioMonitoringConfig.phases` (Liste mit Startversatz, Dauer, Name, Zone). `CardioZoneAlarm` nutzt die Zone der aktuellen Phase. Die Karenzzeit beginnt bei jedem Phasenwechsel neu.
- **Phasenwechsel:**
  - Swift erkennt den Wechsel über den 1-s-Timer bzw. beim nächsten Messwert.
  - Es folgt eine Benachrichtigung „Phase 3/9 · Belastung 4:00 – Ziel 160–172“ mit Ton.
  - Die Live Activity zeigt Phasenname und `Text(timerInterval:)` bis zum Phasenende.
  - Nach der letzten Phase kommt „Vorlage beendet – du kannst beenden oder weiterfahren“. Die Einheit läuft weiter, bis der Nutzer beendet.
- **Timer:** Er läuft im Hintergrund nur, solange der Prozess wach ist. Mit `audio`-Modus (Sprachansagen an) bleibt er zuverlässig wach. Ohne kommt der Phasenwechsel spätestens mit dem nächsten Messwert des Gurts, also ca. 1 s später.

### D4 – Sprachansagen

- **Einstellungen:** `voiceEnabled` (Standard aus) und `voiceIntervalMinutes` (aus, 1, 2, 5, 10).
- **Texte:**
  - „Puls 146, über dem Ziel. Etwas langsamer.“
  - „Puls 118, unter dem Ziel. Etwas schneller.“
  - „Wieder im Zielbereich.“
  - „Phase 3 von 9, Belastung, 4 Minuten, Ziel 160 bis 172.“
  - „12 Minuten, Puls 134.“
- **Technik:**
  - `AVSpeechSynthesizer` mit deutscher Stimme.
  - `AVAudioSession` mit `.playback`, Modus `.voicePrompt`, Optionen `.duckOthers` und `.interruptSpokenAudioAndMixWithOthers`. Nach der Ansage wird die Session mit `.notifyOthersOnDeactivation` deaktiviert.
  - Benachrichtigungen bleiben zusätzlich. Bei aktiver Sprache haben sie keinen Ton, damit nichts doppelt klingt.
