# cardio-session-flow

## ADDED Requirements

### Requirement: Cardio nach dem Krafttraining anbieten

Nach dem Beenden eines aktiven Krafttrainings SHALL die Zusammenfassung „Cardio anhängen“ anbieten, sofern die Einstellung an ist und keine Cardio-Einheit läuft. Ein Tipp auf „Starten“ MUST mit dem gemerkten Gurt und der zuletzt genutzten Vorlage bzw. dem letzten Zielbereich starten.

#### Scenario: Push beendet
- **GIVEN** das Krafttraining „Push“ läuft, zuletzt wurde „Zone 2 – 30 min“ genutzt
- **WHEN** der Nutzer „Push“ beendet und in der Zusammenfassung „Starten“ tippt
- **THEN** läuft eine Cardio-Einheit mit „Zone 2 – 30 min“ und die Live-Ansicht ist offen

#### Scenario: Ausgeschaltet
- **GIVEN** „Cardio nach Krafttraining anbieten“ ist aus
- **WHEN** der Nutzer ein Krafttraining beendet
- **THEN** zeigt die Zusammenfassung keine Cardio-Karte

### Requirement: Intervall-Vorlagen

Der Nutzer SHALL Vorlagen aus Phasen mit Dauer und Zielbereich (Zone oder bpm) wählen, anlegen, ändern und löschen können. Während einer Einheit mit Vorlage MUST der Zielbereich zu Phasenbeginn wechseln, und der Wechsel MUST angekündigt werden, auch bei gesperrtem Display.

#### Scenario: 4×4
- **GIVEN** Maximalpuls 190 und die Vorlage „4×4 (Norwegisch)“
- **WHEN** nach 10 min Aufwärmen die erste Belastungsphase beginnt
- **THEN** gilt Ziel 152–171 bpm und es erscheint „Phase 2/9 · Belastung 4:00 – Ziel 152–171“

#### Scenario: Karenz pro Phase
- **GIVEN** eine Belastungsphase beginnt mit Puls 140 bei Ziel 152–171
- **WHEN** der Puls innerhalb von 15 s auf 155 steigt
- **THEN** erscheint kein Alarm „Puls zu niedrig“

#### Scenario: Zonenvorlage ohne Zonen
- **GIVEN** keine Maximalpuls- oder Altersangabe
- **WHEN** der Nutzer „4×4 (Norwegisch)“ wählt
- **THEN** ist „Starten“ deaktiviert mit Verweis auf die Cardio-Einstellungen

#### Scenario: Vorlage zu Ende
- **GIVEN** die letzte Phase ist abgelaufen
- **WHEN** der Nutzer weiterfährt
- **THEN** läuft die Einheit weiter ohne Zielbereich, bis er beendet

### Requirement: Phasen in der gespeicherten Einheit

Eine Einheit mit Vorlage SHALL Vorlagenname und aufgelöste Phasen speichern. Die Zeit im Zielbereich MUST gegen die jeweils gültige Phase gerechnet werden. Die Pulskurve MUST das Zielband stufenweise je Phase zeigen.

#### Scenario: Zeit im Ziel je Phase
- **GIVEN** Phase 1 (0–5 s, Ziel 110–130) und Phase 2 (5–10 s, Ziel 150–170), Intervall 5 s, Werte 120 und 160
- **WHEN** die Kennzahlen berechnet werden
- **THEN** ist die Zeit im Zielbereich 10 s

### Requirement: Sprachansagen

Sind Sprachansagen eingeschaltet, SHALL die App Zonenalarme, Phasenwechsel und im gewählten Intervall Dauer und Puls auf Deutsch ansagen und andere Audiowiedergabe währenddessen leiser stellen. Standardmäßig MUST die Funktion aus sein.

#### Scenario: Musik läuft
- **GIVEN** Sprachansagen an und Musik läuft
- **WHEN** der Puls 16 s über dem Ziel liegt
- **THEN** wird die Musik leiser, die App sagt „Puls 146, über dem Ziel. Etwas langsamer.“ und die Musik wird wieder lauter

#### Scenario: Intervallansage
- **GIVEN** Sprachansagen alle 5 Minuten
- **WHEN** 10 Minuten vergangen sind
- **THEN** sagt die App „10 Minuten, Puls 134.“
